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

Асинхронный процесс, который отслеживает изменения запускается по расписанию в [Schked](https://github.com/bibendi/schked).

Чтобы этот процесс увидел ваши откладываемые события, вам нужно реализовать таблицу в БД и модель.

```ruby
create_table :my_outbox_items do |t|
  t.string :uuid, null: false
  t.string :event_name, null: false
  t.json :options
  t.binary :proto_payload, null: false
  t.integer :status, null: false, default: 0
  t.integer :errors_count, null: false, default: 0
  t.timestamp :processed_at
  t.timestamps
end

add_index :my_outbox_items, :uuid, unique: true
add_index :my_outbox_items, :status
```

В модели необходимо определить метод `transports`.

```ruby
# app/models/my_outbox_item.rb
class MyOutboxItem < Sbmt::Outbox::Item
  def transports
    [
      MyEventCreatedProducer
    ]
  end
end
```

В геме используется дефолтная ретрай стратегия.
Повтор событий происходит каждый раз, пока количество попыток не достигнет `max_retries`
В конфигурации можно указать экспоненциальный интревал между попытками.
Для этого указывает в конфигах `exponential_retry_interval: true`.
Дополнительно можно передать дополнительные параметры.
Для работы экспоненциальной стратегии, важно, чтобы в модели было поле  `t.timestamp :processed_at`
Также можно передать свою стратегию, определив метод `retry_strategy`

```ruby
# app/models/my_outbox_item.rb
class MyOutboxItem < Sbmt::Outbox::Item
  def retry_strategy
    MyRetryStrategy
  end
end

class MyRetryStrategy
  # Return boolean
  def self.call(outbox_item)
    # my logic
  end
end
```

Мы почти у цели — осталось определить нужный нам продьюсер событий и пару конфигов.

```ruby
# app/producers/my_event_created_producer.rb

class OrderCreatedProducer < Sbmt::Outbox::BaseProducer
  option :topic, default: lambda {
    config.dig(:producer, :topics, :my_event_created)
  }

  def publish(outbox_item, payload)
    publish_to_kafka(payload, outbox_item.options)
  end
end
```

```yaml
# config/outbox.yml

default: &default
  ignore_kafka_errors: true
  items:
    my_outbox_item:
      partition_size: 2 # default: 1
      max_retries: 1 # default: 0
      exponential_retry_interval: true # Enable exponential interval between attempts to process an outbox item. Default: false
      minimal_retry_interval: 10 # default: 10
      maximal_retry_interval: 600 # default: 600
      multiplier_retry_interval: 2 # default: 2

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
  config.item_classes << "MyOutboxItem"
  config.paths << Rails.root.join("config/outbox.yml").to_s
end
```

## Usage

```ruby
Sbmt::Outbox::CreateItem.call(MyOutboxItem, attributes: some_attrs)
```

## Development & Test

### Installation

- Install [Dip](https://github.com/bibendi/dip)
- Run `dip provision`

### Usage

- Run `dip setup`
- Run `dip test`

See more commands at [dip.yml](./dip.yml).
