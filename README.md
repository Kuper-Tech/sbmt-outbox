# Outbox

Микросервисы часто публикуют события после выполнения транзакции базы данных. Запись в базу данных и публикация события — это две разные транзакции, и они должны быть атомарными. Отказ опубликовать событие может означать критический отказ бизнес-процесса.

Outbox pattern обеспечивает эффективное решение для надежной публикации событий. Идея этого подхода заключается в том, чтобы иметь таблицу «Исходящие» в базе данных сервиса. При завершении основной транзакции в базе данных выполняется не только вставка или обновление данных , но и запись, представляющая событие, также вставляется в таблицу outbox items. Два действия базы данных выполняются как часть одной транзакции.

Асинхронный процесс отслеживает в таблице исходящих сообщений новые записи и, если они есть, публикует события в шине событий. Шаблон просто разделяет две транзакции на разные сервисы, повышая надежность.

Read more about Outbox patter at https://microservices.io/patterns/data/transactional-outbox.html

PaaS implementation https://gitlab.sbmt.io/paas/rfc/-/blob/master/text/paas-2219-outbox/README.md

## Installation

```ruby
source "https://nexus.sbmt.io/repository/ruby-gems-sbermarket/" do
  gem "sbmt-outbox"
end
```

## Configuration

### Outbox pattern

Асинхронный процесс, который отслеживает изменения запускается по расписанию в [Schked](https://github.com/bibendi/schked).

Чтобы этот процесс увидел ваши откладываемые события, вам нужно реализовать таблицу в БД и модель.

```ruby
create_table :my_outbox_items do |t|
  t.string :uuid, null: false
  t.string :event_name, null: false # optional, use it when you have several events per one outbox table
  t.string :event_key, null: false # optional, use it when you use compacted-log retry strategy
  t.jsonb :options
  t.binary :proto_payload, null: false
  t.integer :status, null: false, default: 0
  t.integer :errors_count, null: false, default: 0
  t.timestamp :processed_at
  t.timestamps
end

add_index :my_outbox_items, :uuid, unique: true
add_index :my_outbox_items, :status
add_index :my_outbox_items, [:event_name, :event_key]
```

В модели необходимо определить метод `transports`.

```ruby
# app/models/my_outbox_item.rb
class MyOutboxItem < Sbmt::Outbox::OutboxItem
  PRODUCER = Sbmt::Outbox::BaseProducer[
    name: 'order_created',
    topic: Sbmt::Outbox.yaml_config.dig(:producer, :topics, :my_event_created)
  ]

  def transports
    [ PRODUCER ]
  end
end
```

Мы почти у цели — осталось определить пару конфигов.

```yaml
# config/outbox.yml

default: &default
  ignore_kafka_errors: true
  outbox_items:
    my_outbox_item:
      retention: P1W # https://en.wikipedia.org/wiki/ISO_8601#Durations
      partition_size: 2 # default: 1
      max_retries: 3 # default: 0

development:
  <<: *default

test:
  <<: *default

staging:
  <<: *default
  ignore_kafka_errors: false

production:
  <<: *default
  ignore_kafka_errors: false
```

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.outbox_item_classes << "MyOutboxItem"
  config.paths << Rails.root.join("config/outbox.yml").to_s
end
```

### Inbox pattern

Обратный процесс. Здесь мы принимаем наши события.

Создаем таблицу в БД и модель.

```ruby
create_table :my_inbox_items do |t|
  t.string :uuid, null: false
  t.string :event_name, null: false # optional, use it when you have several events per one inbox table
  t.string :event_key, null: false # optional
  t.jsonb :options
  t.binary :proto_payload, null: false
  t.integer :status, null: false, default: 0
  t.integer :errors_count, null: false, default: 0
  t.timestamp :processed_at
  t.timestamps
end

add_index :my_inbox_items, :uuid, unique: true
add_index :my_inbox_items, :status
add_index :my_inbox_items, [:event_name, :event_key]
```

В модели необходимо определить метод `transports`.

```ruby
# app/models/my_inbox_item.rb
class MyInboxItem < Sbmt::Inbox::Item
  HANDLER = ->(item, proto_payload) do
    Success()
  end

  def transports
    [ HANDLER ]
  end
end
```

```yaml
# config/outbox.yml

  inbox_items:
    my_inbox_item:
      retention: P1W # https://en.wikipedia.org/wiki/ISO_8601#Durations
      partition_size: 2 # default: 1
      max_retries: 3 # default: 0
```

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.inbox_item_classes << "MyInboxItem"
end
```

#### Retry strategies

В геме используется несколько видов стратегий для повторения обработок события в случае ошибки. Стратегии можно комбинировать — они будут запускаться по очереди. Каждая стратегия принимает одно из трех решений: обработать сообщение сейчас; пропустить обработку; пометить сообщение как не нуждающееся в обработке.

##### Exponential backoff

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

##### Compacted log

Данная стратегия необходима, если используется [Kafka log compaction](https://habr.com/ru/company/sberbank/blog/590045/).

```ruby
change_table :my_outbox_items do |t|
  t.bigint :event_key, null: false
end

add_index :my_outbox_items, [:event_key], where: "status = 2"
```

```yaml
# config/outbox.yml

  outbox_items:
    my_outbox_item:
      ...
      retry_strategies:
        - exponential_backoff
        - compacted_log
```

Если вы хотите (и должны хотеть) использовать вместе с `exponential_backoff`, то у убедитесь в том, что `compacted_log` идет последней, для минимизации запросов в БД.

### Dead letters pattern

Если наш Kafka consumer не смог обработать сообщение, то оно откладывается в специальную таблицу в базе данных.

```ruby
  create_table :my_dead_letters, id: :bigint do |t|
    t.binary :proto_payload, null: false
    t.json :metadata
    t.string :topic_name, null: false
    t.text :error
    t.timestamps
  end
```

В модели необходимо определить методы `handler` и `payload`.

```ruby
# app/models/my_dead_letter.rb
class MyDeadLetter < Sbmt::Outbox::DeadLetter
  def handler
    MyConsumerHandler
  end

  def payload
    MyDecoder.decode(proto_payload)
  end
end
```

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  ...
  config.dead_letter_classes << 'MyDeadLetter'
end
```

## Usage


### Create outbox item

```ruby
transaction do
  some_record.save!

  result = Sbmt::Outbox::CreateItem.call(MyOutboxItem, attributes: some_attrs)
  raise result.failure unless result.success?
end
```

### Create inbox dead letter

```ruby
result = handle(message.payload)
return if result.success?

result = Sbmt::Outbox::CreateDeadLetter.call(
  MyDeadLetter,
  proto_payload: message.raw_payload,
  topic_name: message.metadata.topic,
  metadata: message.metadata,
  error: error
)

raise result.failure unless result.success?
```

Для повторения процессинга событий, существует rake task:

```sh
rake outbox:process_dead_letters[MyDeadLetter,1,2,3,8]
```

## Development & Test

### Installation

- Install [Dip](https://github.com/bibendi/dip)
- Run `dip provision`

### Usage

- Run `dip setup`
- Run `dip test`

See more commands at [dip.yml](./dip.yml).
