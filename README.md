# Outbox

Микросервисы часто публикуют события после выполнения транзакции базы данных. Запись в базу данных и публикация события — это две разные транзакции, и они должны быть атомарными. Отказ опубликовать событие может означать критический отказ бизнес-процесса.

Outbox pattern обеспечивает эффективное решение для надежной публикации событий. Идея этого подхода заключается в том, чтобы иметь таблицу «Исходящие» в базе данных сервиса. При завершении основной транзакции в базе данных выполняется не только вставка или обновление данных , но и запись, представляющая событие, также вставляется в таблицу outbox items. Два действия базы данных выполняются как часть одной транзакции.

Асинхронный процесс отслеживает в таблице исходящих сообщений новые записи и, если они есть, публикует события в шине событий. Шаблон просто разделяет две транзакции на разные сервисы, повышая надежность.

Read more about Outbox patter at https://microservices.io/patterns/data/transactional-outbox.html

PaaS implementation https://gitlab.sbmt.io/paas/rfc/-/blob/master/text/paas-2219-outbox/README.md

Gem реализован как самостоятельный демон.

## Installation

```ruby
source "https://nexus.sbmt.io/repository/ruby-gems-sbermarket/" do
  gem "sbmt-outbox"
end
```

```shell
bundle install
```

## Auto configuration

Для упрощения настройки и создания inbox/outbox items реализованы rails-генераторы

### Настройка первоначальной конфигурации гема

Если вы подключаете outbox в свое приложения впервые, можно сгенерировать первоначальную базовую конфигурацию:

```shell
bundle exec rails g outbox:install
```

В результате будут созданы основные конфиги гема, более подробно ознакомиться с перечнем опций можно так:

```shell
bundle exec rails g outbox:install --help
```

### Создание inbox/outbox-items

Сгенерировать inbox/outbox-item можно следующим образом:

```shell
bundle exec rails g outbox:item MaybeNamespaced::Model::InboxItem --kind inbox
bundle exec rails g outbox:item MaybeNamespaced::Model::OutboxItem --kind outbox
```

В результате будут созданы: миграция, модель, преднастроены файлы конфигурации гема для использования создаваемого item

Более подробно перечень опций генератора можно посмотреть в help:

```shell
bundle exec rails g outbox:item --help
```

### Добавление транспорта

Чтобы добавить транспорт, выполните

```shell
bin/rails g outbox:transport MaybeNamespaced::Model::OutboxItem some/transport/name --kind outbox
bin/rails g outbox:transport MaybeNamespaced::Model::InboxItem some/transport/name --kind inbox
```

Подробнее см.
```shell
bin/rails g outbox:transport -h
```


## Manual configuration

### Outbox pattern

Чтобы процесс увидел ваши откладываемые события, вам нужно реализовать таблицу в БД и модель.

```ruby
create_table :my_outbox_items do |t|
  t.uuid :uuid, null: false
  t.string :event_name, null: false # optional, use it when you have several events per one outbox table
  t.string :event_key, null: false
  t.integer :bucket, null: false
  t.integer :status, null: false, default: 0
  t.jsonb :options
  t.binary :proto_payload, null: false
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

Вы можете объединить несколько событий через одну таблицу, для этого нужно объявить колонку `event_name`. Такой подход оправдан только в случае, когда предполагается, что событий будет не очень много, а также у таких событий будет одинаковые политики retention и retry.

```ruby
# app/models/my_outbox_item.rb
class MyOutboxItem < Sbmt::Outbox::OutboxItem
  validates :event_name, presence: true # optional
end
```

Если вы используете Кафку в качестве транспорта, то рекомендуется использовать для этого гем sbmt-kafka_producer.

Мы почти у цели — осталось определить пару конфигов.

```yaml
# config/outbox.yml

default: &default
  owner: foo-team
  bucket_size: 16
  probes:
    port: 5555 # default: 5555

  outbox_items:
    my_outbox_item:
      owner: my_outbox_item_team
      retention: P1W # https://en.wikipedia.org/wiki/ISO_8601#Durations
      partition_size: 2 # default: 1
      max_retries: 3 # default: 0
      transports:
        sbmt/kafka_producer:
          topic: "my-topic-name"

development:
  <<: *default

test:
  <<: *default
  bucket_size: 2

production:
  <<: *default
  bucket_size: 256
```

**NOTE:**  `HttpHealthCheck` запускается всегда при старте демона, если в конфиге отсутствует ключ `probes` используется дефолтный порт `5555` для их запуска

Если в событиях используется `event_name` то транспорты указываются в таком формате:

```yaml
outbox_items:
  my_outbox_item:
    transports:
      - class: sbmt/kafka_producer
        event_name: "order_created"
        topic: "order_created_topic"
      - class: sbmt/kafka_producer
        event_name: "orders_completed"
        topic: "orders_completed_topic"
```

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.redis = {url: ENV.fetch("REDIS_URL")}
  config.outbox_item_classes << "MyOutboxItem"
  config.paths << Rails.root.join("config/outbox.yml").to_s

  config.process_items.tap do |x|
    x[:general_timeout] = 180 # максимальное время обработки батча, после которого батч будет считаться зависшим и обработка будет прервана
    x[:cutoff_timeout] = 60 # максимально время обработки батча, после которого обработка батча будет прервана в текущем потоке, а следующий подхвативший поток начнет обработку батча с того же места
    x[:batch_size] = 200 # размер батча
  end

  config.worker.tap do |worker|
    worker[:rate_limit] = 10 # количество батчей, которое один поток обработает за rate_interval
    worker[:rate_interval] = 60 # секунды
  end
end
```

### Inbox pattern

Обратный процесс. Здесь мы принимаем наши события.

Создаем таблицу в БД и модель.

```ruby
create_table :my_inbox_items do |t|
  t.uuid :uuid, null: false
  t.string :event_name, null: false # optional, use it when you have several events per one inbox table
  t.string :event_key, null: false
  t.integer :bucket, null: false
  t.integer :status, null: false, default: 0
  t.jsonb :options
  t.binary :proto_payload, null: false
  t.integer :errors_count, null: false, default: 0
  t.text :error_log
  t.timestamp :processed_at
  t.timestamps
end

add_index :my_inbox_items, :uuid, unique: true
add_index :my_inbox_items, [:status, :bucket]
add_index :my_inbox_items, [:event_name, :event_key]
add_index :my_inbox_items, :created_at
```

Вы можете объединить несколько событий через одну таблицу, для этого нужно объявить колонку `event_name`. Такой подход оправдан только в случае, когда предполагается, что событий будет не очень много, а также у таких событий будет одинаковые политики retention и retry.

```ruby
# app/models/my_inbox_item.rb
class MyInboxItem < Sbmt::Inbox::InboxItem
end

# app/services/import_order.rb
class ImportOrder
  def initialize(source:)
  end

  def call(outbox_item, payload)
  end
end
```

```yaml
# config/outbox.yml

  inbox_items:
    my_inbox_item:
      owner: my_inbox_item_team
      retention: P1W # https://en.wikipedia.org/wiki/ISO_8601#Durations
      partition_size: 2 # default: 1
      max_retries: 3 # default: 0
      transports:
        import_order:
          source: "kafka"
```

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.inbox_item_classes << "MyInboxItem"
end
```

### Retry strategies

В геме используется несколько видов стратегий для повторения обработок события в случае ошибки. Стратегии можно комбинировать — они будут запускаться по очереди. Каждая стратегия принимает одно из трех решений: обработать сообщение сейчас; пропустить обработку; пометить сообщение как не нуждающееся в обработке.

#### Exponential backoff

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

Данная стратегия необходима, если используется [Kafka log compaction](https://habr.com/ru/company/sberbank/blog/590045/).

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

### Partition strategies

В зависимости от того, какой типа данных используется в `event_key` необходимо выбрать правильную стратегию для выбора партиции.

#### Number partitioning

Используется когда типа данных число или строка, содержащая число, например `some-chars-123`. В случае строки все нечисловые символы вырезаются и остаются только цифры. Стратегия используется по умолчанию.

```yaml
# config/outbox.yml

  outbox_items:
    my_outbox_item:
      ...
      partition_strategy: number
```

#### Hash partitioning

Стратегия полезна в случае использования uuid в качестве типа данных для `event_key`.

```yaml
# config/outbox.yml

  outbox_items:
    my_outbox_item:
      ...
      partition_strategy: hash
```

### Concurrency

Демон outbox использует Ruby threads для конкурентной обработки сообщений, содержащихся в таблице.
Количество потоков задается через параметр `--concurrency`. Если параметр не передан, то по умолчанию запускается 10 потоков.
Также в CLI можно передать параметр `--box`, который определяет какие конкретно outbox/inbox таблицы должен обрабатывать конкретный процесс. Если параметр на задан, то демон обрабатывает все доступные таблицы. Помимо этого, можно указать какие партиции для таблицы должен обрабатывать процесс, для этого нужно передать параметр в следующем формате: `--box some_outbox:1,2,3`.

В конфиге `outbox.yml` можно также встретить настройку `bucket_size`. Когда создается outbox/inbox item, то в зависимости от стратегии партиционирования, высчитывается колонка `bucket` в пределах размера `bucket_size`. Далее при старте демона все бакеты мапятся в партиции, количество которых задается через `partition_size`. Например, если bucket_size=4 и partition_size=2, то bucket_0 и bucket_2 принадлежат partition_0, а bucket_1 и bucket_3 принадлежат partition_1. **Важно!** когда выбираете значения для bucket_size и partition_size, необходимо чтобы `bucket_size` делился без остатка на `partition_size`, иначе получится неравномерное распределение бакетов между партициями. Такая система с бакетами сделана для того, чтобы можно было практически налету масштабировать обработку сообщений, не останавливая всё приложение, а только изменяя настройку partition_size и перезапуская только демон. Также важно изначально оценить потенциальный объем сообщений, чтобы выбрать правильное значение для `bucket_size`, так как изменить его в дальнейшем будет очень проблематично, но и переусердствовать не стоит, так как слишком большое значение `bucket_size` и маленькое значение `partition_size` может замедлить выборку сообщений из таблицы.

В один момент времени невозможна обработка одной и той же партиции в разных потоках, даже если эти потоки находятся в разных процессах. За счет этого обеспечивается хронологическая обработка сообщений с одинаковыми `event_key`.

Пример конфигурации. Допустим в качестве транспорта для outbox используется Kafka producer. В топике Kafka 18 партиций. Тут важно понимать, что нам не надо завязываться точь-в-точь на количество партиций в топике, мы просто ориентируемся на эти цифры, потому что партиции в outbox с ними ни как не связаны. Если у нас bucket_size=256, то тогда мы можем сделать partition_size=16. Количество процессов (реплик) можем сделать 4, в каждом по 4 потока.

### Middlewares

Обработку событий можно обвернуть в middlewares.
Чтобы добавить middleware для процесса обработки партиции, необходимо указать в конфиге его класс:

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

Также возможно обернуть обработку каждого события в отдельные middlewares

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.item_process_middlewares.push(
    'MyItemMiddleware'
  )
end

# my_item_middleware.rb

class MyItemMiddleware
  def call(job, item_id)
    # your code
    yield
    # your code
  end
end
```

В обоих случаях, при добавление двух и более middlewares, порядок выполнения зависит от порядка, заданного в конфигурации гема.

```ruby
# config/initializers/outbox.rb

Rails.application.config.outbox.tap do |config|
  config.item_process_middlewares.push(
    'MyFirstItemMiddleware', # выполнится первым
    'MySecondItemMiddleware' # выполнится вторым
  )
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
