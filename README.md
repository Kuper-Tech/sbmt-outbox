[![Gem Version](https://badge.fury.io/rb/sbmt-outbox.svg)](https://badge.fury.io/rb/sbmt-outbox)
[![Build Status](https://github.com/SberMarket-Tech/sbmt-outbox/workflows/Ruby/badge.svg?branch=master)](https://github.com/SberMarket-Tech/sbmt-outbox/actions?query=branch%3Amaster)

# Sbmt-Outbox

Microservices often publish messages after a transaction is committed. Writing to the database and publishing the message are two separate transactions, so they must be atomic. An unsuccessful publication of a message can lead to critical failure of the business process.

Outbox pattern provides a reliable solution for message publication. The idea of this approach is to have an "outgoing messages table" in the service database. Before the main transaction finishes, a message row is inserted in this table. Thus, two actions are performed as part of a single transaction. An asynchronous process pulls new rows from the database table, and if they exist it publishes messages to the broker.

Read more about the Outbox pattern at https://microservices.io/patterns/data/transactional-outbox.html

## Installation

Add this line to your application's Gemfile:

```ruby
gem "sbmt-outbox"
```

And then execute:

```shell
bundle install
```

## Auto configuration

We recommend going through configuration and files creation with the following Rails generators.

Each generator can be run using the `--help` option to learn more about the available arguments.

### Initial configuration

If you plug the gem into your application for the first time, you can generate the initial configuration:

```shell
rails g outbox:install
```

### Outbox/inbox items creation

An Active Record model for the outbox/inbox item can be generated like this:

```shell
rails g outbox:item MaybeNamespaced::SomeOutboxItem --kind outbox
rails g outbox:item MaybeNamespaced::SomeInboxItem --kind inbox
```

In the result, a migration and a model will be created, and the `outbox.yml` file will be configured.

### Transport creation

A transport — is a class that will be invoked while processing the specific outbox/inbox item. The transport must return a boolean value or a Dry monads result.

```shell
rails g outbox:transport MaybeNamespaced::SomeOutboxItem some/transport/name --kind outbox
rails g outbox:transport MaybeNamespaced::SomeInboxItem some/transport/name --kind inbox
```

## Usage

To create an outbox item, you should call an interactor with the item model class and `event_key`. The last one will be the partitioning key.

```ruby
transaction do
  some_record.save!

  result = Sbmt::Outbox::CreateOutboxItem.call(
    MyOutboxItem,
    event_key: some_record.id,
    attributes: {
      payload: some_record.generate_payload,
      options: {
        key: some_record.id, # optional, may be used when producing to a Kafka topic
        headers: {'FOO_BAR' => 'baz'} # optional, you can add custom headers
      }
    }
  )

  raise result.failure unless result.success?
end
```

## Monitoring

We use [Yabeda](https://github.com/yabeda-rb/yabeda) to collect [all kind of metrics](./config/initializers/yabeda.rb).

Example of Grafana Dashboard that you can import [from a file](./examples/grafana-dashboard.json):

![Grafana Dashboard](./examples/outbox-grafana-preview.png)

[Full picture](./examples/outbox-grafana.png)

## Manual configuration

### Outbox pattern

You should create a database table in order for the process to see your outgoing messages.

```ruby
create_table :my_outbox_items do |t|
  t.uuid :uuid, null: false
  t.string :event_name, null: false # optional, use it when you have several events per one outbox table
  t.string :event_key, null: false
  t.integer :bucket, null: false
  t.integer :status, null: false, default: 0
  t.jsonb :options
  t.binary :payload, null: false # when using mysql the column type should be mediumblob
  t.integer :errors_count, null: false, default: 0
  t.text :error_log
  t.timestamp :processed_at
  t.timestamps
end

add_index :my_outbox_items, :uuid, unique: true
add_index :my_outbox_items, [:status, :bucket]
add_index :my_outbox_items, [:event_name, :event_key]
add_index :my_outbox_items, :created_at
```

You can combine several types of messages in the single table. For that, you should define an `event_name` column in the table. This approach is justified only if it is assumed that there will not be very many events, and such events will have the same retention and retry policies.

```ruby
# app/models/my_outbox_item.rb
class MyOutboxItem < Sbmt::Outbox::OutboxItem
  validates :event_name, presence: true # optional
end
```

The `outbox.yml` config is a main config for the gem where are located parameters for each outbox/inbox item class.

```yaml
# config/outbox.yml
default: &default
  owner: foo-team # optional, used in Yabeda metrics
  bucket_size: 16 # optional, default 16, see into about the buckets at the #Concurrency section
  probes:
    port: 5555 # default, used for Kubernetes probes

  outbox_items: # outbox items section
    my_outbox_item: # underscored model class name
      owner: my_outbox_item_team # optional, used in Yabeda metrics
      retention: P1W # retention period, https://en.wikipedia.org/wiki/ISO_8601#Durations
      partition_size: 2 # default 1, partitions count
      max_retries: 3 # default 0, the number of retries before the item will be marked as failed
      transports: # transports section
        produce_message: # underscored transport class name
          topic: "my-topic-name" # default transport arguments

development:
  <<: *default

test:
  <<: *default
  bucket_size: 2

production:
  <<: *default
  bucket_size: 256
```

```ruby
# app/services/import_order.rb
class ProduceMessage
  def initialize(topic:)
    @topic = topic
  end

  def call(outbox_item, payload)
    # send message to topic
    true # mark message as processed
  end
end
```

If you use Kafka as a transport, it is recommended to use the sbmt-kafka_producer gem for this.

The transports are defined in the following format when `event_name` is used:

```yaml
outbox_items:
  my_outbox_item:
    transports:
      - class: produce_message
        event_name: "order_created" # event name marker
        topic: "order_created_topic" # some transport default argument
      - class: produce_message
        event_name: "orders_completed"
        topic: "orders_completed_topic"
```

The `outbox.rb` contains overall general configuration:

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.redis = {url: ENV.fetch("REDIS_URL")} # Redis is used as a coordinator service
  config.paths << Rails.root.join("config/outbox.yml").to_s # optional; configuration file paths, deep merged at the application start, useful with Rails engines

  # optional
  config.process_items.tap do |x|
    # maximum processing time of the batch, after which the batch will be considered hung and processing will be aborted
    x[:general_timeout] = 180
    # maximum batch processing time, after which the processing of the batch will be aborted in the current thread,
    # and the next thread that picks up the batch will start processing from the same place
    x[:cutoff_timeout] = 60
    # batch size
    x[:batch_size] = 200
  end

  # optional
  config.worker.tap do |worker|
    # number of batches that one thread will process per rate interval
    worker[:rate_limit] = 10
    # rate interval in seconds
    worker[:rate_interval] = 60
  end
end
```

### Inbox pattern

The database migration will be the same as described at the Outbox pattern.

```ruby
# app/models/my_inbox_item.rb
class MyInboxItem < Sbmt::Outbox::InboxItem
end
```

```yaml
# config/outbox.yml
# see main configuration at the Outbox pattern
inbox_items: # inbox items section
  my_inbox_item: # underscored model class name
    owner: my_inbox_item_team # optional, used in Yabeda metrics
    retention: P1W # retention period, https://en.wikipedia.org/wiki/ISO_8601#Durations
    partition_size: 2 # default 1, partitions count
    max_retries: 3 # default 0, the number of retries before the item will be marked as failed
    transports: # transports section
      import_order: # underscored transport class name
        source: "kafka" # default transport arguments
```

```ruby
# app/services/import_order.rb
class ImportOrder
  def initialize(source:)
    @source = source
  end

  def call(outbox_item, payload)
    # some work to create order in the database
    true # mark message as processed
  end
end
```

If you use Kafka, it is recommended to use the sbmt-kafka_consumer gem for this.

### Retry strategies

The gem uses several types of strategies to repeat a message processing in case of an error. Strategies can be combined — they will be launched in turn. Each strategy makes one of three decisions: process a message; skip processing a message; skip processing and mark message as skipped for future processing.

#### Exponential backoff

This strategy periodically retries a failed messages with increasing delays between message processing.

```yaml
# config/outbox.yml
outbox_items:
  my_outbox_item:
    ...
    minimal_retry_interval: 10 # default: 10
    maximal_retry_interval: 600 # default: 600
    multiplier_retry_interval: 2 # default: 2
    retry_strategies:
      - exponential_backoff
```

#### Compacted log

This strategy ensures idempotency. In short, if a message fails and a later message with the same event_key has already been delivered, then you most likely do not want to re-deliver the first one when it is retried.

```yaml
# config/outbox.yml
outbox_items:
  my_outbox_item:
    ...
    retry_strategies:
      - exponential_backoff
      - compacted_log
```

The exponential backoff strategy should be used in conjunction with the compact log strategy, and it should come last to minimize the number of database queries.

### Partition strategies

Depending on which data type is used in the `event_key`, it is necessary to choose the right partition strategy.

#### Number partitioning

This strategy should be used when `event_key` contains a number, for example `52523` or `some-chars-123`. All characters that are not numbers will be deleted, and only numbers will remain. The strategy is used by default.

```yaml
# config/outbox.yml
outbox_items:
  my_outbox_item:
    ...
    partition_strategy: number
```

#### Hash partitioning

This strategy should be used when `event_key` is a string or uuid.

```yaml
# config/outbox.yml
outbox_items:
  my_outbox_item:
    ...
    partition_strategy: hash
```

## Concurrency

Outbox Daemon CLI uses Ruby threads for concurrent processing of messages pulled from the database table. The number of threads is configures using a `--concurrency` option. By default it's 10 unless the param is provided. You can run several daemons at the same time. The number of partitions per outbox item class is set by `partition_size` config option. Each outbox item partition will be processed one at a time by some daemon. Each partition batch serves several buckets. The bucket is a number in the row in the `bucket` column generated by the partition strategy based on `event_key` column when the message was committed to the database in the range from zero to `bucket_size`. Thus, each outbox table has several partitions which has several buckets. Take a note, you must not to have `partition_size` larger then `bucket_size`. This architecture was made to have an ability to scale daemons without stopping of the entire system to avoid mixing messages in chronological order. So, if you need more partitions, you should just stop the daemons, configure `partition_size`, and start them again.

**Example** Suppose you have a Kafka topic with 18 partitions. The `bucket_size` is 256. We can set `partition_size` to 16 if we expect a slow payload generation. Therefore we should run 4 daemons with 4 threads each to maximum utilize the partitions.

### Middlewares

You can wrap the item processing within middlewares. There are 3 types:
- client middlewares — triggered outside of a daemon; executed alongside an item is created
- server middlewares - triggered inside a daemon; divided by two types:
  - batch middlewares — executed alongside a batch is fetched from the database
  - item middlewares —executed alongside an item is processed

The order of execution depends on the order defined in the outbox config:

```ruby
# config/initializers/outbox.rb
Rails.application.config.outbox.tap do |config|
  config.item_process_middlewares.push(
    'MyFirstItemMiddleware', # goes first
    'MySecondItemMiddleware' # goes second
  )
end
```

#### Client middlewares

```ruby
# config/initializers/outbox.rb
Rails.application.config.outbox.tap do |config|
  config.create_item_middlewares.push(
    'MyCreateItemMiddleware'
  )
end

# my_create_item_middleware.rb
class MyCreateItemMiddleware
  def call(item_class, item_attributes)
    # your code
    yield
    # your code
  end
end
```

#### Server middlewares

Example of a batch middleware:

```ruby
# config/initializers/outbox.rb
Rails.application.config.outbox.tap do |config|
  config.batch_process_middlewares.push(
    'MyBatchMiddleware'
  )
end

# my_batch_middleware.rb
class MyBatchMiddleware
  def call(job)
    # your code
    yield
    # your code
  end
end
```

Example of an item middleware:

```ruby
# config/initializers/outbox.rb
Rails.application.config.outbox.tap do |config|
  config.item_process_middlewares.push(
    'MyItemMiddleware'
  )
end

# my_create_item_middleware.rb
class MyItemMiddleware
  def call(item)
    # your code
    yield
    # your code
  end
end
```

## Tracing

The gem is optionally integrated with OpenTelemetry. If your main application has `opentelemetry-*` gems, the tracing will be configured automatically.

## CLI Arguments

| Key                   | Description                                                               |
|-----------------------|---------------------------------------------------------------------------|
| `--boxes or -b`       | Outbox/Inbox processors to start`                                         |
| `--concurrency or -c` | Number of threads. Default 10.                                            |

## Development & Test

### Installation

- Install [Dip](https://github.com/bibendi/dip)
- Run `dip provision`

### Usage

- Run `dip setup`
- Run `dip test`

See more commands at [dip.yml](./dip.yml).
