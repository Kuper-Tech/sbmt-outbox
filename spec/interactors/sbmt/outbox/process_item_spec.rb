# frozen_string_literal: true

require "ostruct"

describe Sbmt::Outbox::ProcessItem do
  describe "#call" do
    subject(:result) { described_class.call(OutboxItem, outbox_item.id, worker_version: worker_version, redis: redis) }

    let(:redis) { nil }
    let(:worker_version) { 1 }
    let(:max_retries) { 0 }
    let(:producer) { instance_double(Producer, call: true) }
    let(:dummy_middleware_class) { instance_double(Class, new: dummy_middleware) }
    let(:dummy_middleware) { ->(*_args, &b) { b.call } }

    before do
      allow(Producer).to receive(:new).and_return(producer)
      allow_any_instance_of(Sbmt::Outbox::OutboxItemConfig).to receive(:max_retries).and_return(max_retries)
      allow(Sbmt::Outbox).to receive(:item_process_middlewares).and_return([dummy_middleware_class])
      allow(dummy_middleware).to receive(:call).and_call_original
    end

    context "when outbox item is not found in db" do
      let(:outbox_item) { OpenStruct.new(id: 1, options: {}) }

      it "returns error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
          .with(/Failed processing outbox item with error: not found/, stacktrace: nil)
        expect(result).not_to be_success
        expect(dummy_middleware).not_to have_received(:call)
        expect(result.failure).to eq :not_found
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.fetch_error_counter).by(1)
      end
    end

    context "when outbox item is being processed concurrently" do
      let(:outbox_item) { create(:outbox_item) }
      let(:error_msg) { "Mysql2::Error::TimeoutError: Lock wait timeout exceeded; try restarting transaction" }

      before do
        allow(OutboxItem).to receive(:lock).and_raise(
          ActiveRecord::LockWaitTimeout.new(error_msg)
        )
      end

      it "logs failure" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        allow(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result.failure).to eq(error_msg)
        expect(Sbmt::Outbox.logger)
          .to have_received(:log_failure)
          .with(/#{error_msg}/, stacktrace: kind_of(String))
      end

      it "does not call middleware" do
        result
        expect(dummy_middleware).not_to have_received(:call)
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.fetch_error_counter).by(1)
      end
    end

    context "when there is cached item data" do
      let(:redis) { RedisClient.new(url: ENV["REDIS_URL"]) }
      let(:cached_errors_count) { 99 }
      let(:db_errors_count) { 1 }
      let(:max_retries) { 7 }

      before do
        data = Sbmt::Outbox::V2::RedisItemMeta.new(errors_count: cached_errors_count, error_msg: "Some error")
        redis.call("SET", "outbox:outbox_item:#{outbox_item.id}", data.to_s)

        allow_any_instance_of(Sbmt::Outbox::OutboxItemConfig).to receive(:max_retries).and_return(max_retries)
      end

      context "when worker_version is 1" do
        let(:outbox_item) { create(:outbox_item) }
        let(:worker_version) { 1 }

        it "does not use cached data" do
          expect { result }.not_to change { outbox_item.reload.errors_count }
        end
      end

      context "when worker_version is 2" do
        let(:outbox_item) { create(:outbox_item, errors_count: db_errors_count) }
        let(:worker_version) { 2 }

        before do
          allow(Sbmt::Outbox.logger).to receive(:log_failure)
        end

        context "when cached errors_count exceed max retries" do
          it "increments cached errors count and marks items as failed" do
            expect(Sbmt::Outbox.logger).to receive(:log_failure).with(/max retries exceeded: marking item as failed based on cached data/, any_args)
            expect { result }
              .to change { outbox_item.reload.errors_count }.from(1).to(100)
              .and change { outbox_item.reload.status }.from("pending").to("failed")
          end
        end

        context "when cached errors_count is greater" do
          let(:cached_errors_count) { 2 }

          it "sets errors_count based on cached data" do
            expect(Sbmt::Outbox.logger).to receive(:log_failure).with(/inconsistent item: cached_errors_count:2 > db_errors_count:1: setting errors_count based on cached data/, any_args)
            expect { result }
              .to change { outbox_item.reload.errors_count }.from(1).to(2)
              .and change { outbox_item.reload.status }.from("pending").to("delivered")
          end
        end

        context "when cached errors_count is less" do
          let(:cached_errors_count) { 0 }

          it "sets errors_count based on db data" do
            expect { result }
              .to not_change { outbox_item.reload.errors_count }
              .and change { outbox_item.reload.status }.from("pending").to("delivered")
          end
        end
      end
    end

    context "when outbox item is not in pending state" do
      let(:outbox_item) do
        create(
          :outbox_item,
          status: Sbmt::Outbox::BaseItem.statuses[:failed]
        )
      end

      it "doesn't report error" do
        expect(Sbmt::Outbox.error_tracker).not_to receive(:error)
        allow(Sbmt::Outbox.logger).to receive(:log_info)
        expect(result).not_to be_success
        expect(Sbmt::Outbox.logger).to have_received(:log_info).with("already processed")
        expect(dummy_middleware).not_to have_received(:call)
        expect(result.failure).to eq :already_processed
      end
    end

    context "when there is no any transport" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:transports).and_return(nil)
      end

      it "returns error" do
        expect(result).not_to be_success
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "does not call middleware" do
        result
        expect(dummy_middleware).not_to have_received(:call)
      end

      it "tracks error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)

        expect(result.failure).to eq :missing_transports
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end
    end

    context "when outbox item produce to transport successfully" do
      let!(:outbox_item) { create(:outbox_item) }

      it "returns success" do
        expect(Sbmt::Outbox.error_tracker).not_to receive(:error)
        allow(Sbmt::Outbox.logger).to receive(:log_success)
        expect(Sbmt::Outbox.logger).to receive(:log_success).with(/delivered/, any_args)
        expect(result).to be_success
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
        expect(outbox_item.reload).to be_delivered
      end

      it "tracks Yabeda sent counter and last_sent_event_id and process_latency" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.sent_counter).by(1)
          .and update_yabeda_gauge(Yabeda.outbox.last_sent_event_id)
          .and measure_yabeda_histogram(Yabeda.outbox.process_latency)
      end
    end

    context "when combined outbox item produce to transport successfully" do
      let!(:outbox_item) { create(:combined_outbox_item) }

      it "tracks Yabeda sent counter and last_sent_event_id and process_latency with proper box name" do
        expect { described_class.call(Combined::OutboxItem, outbox_item.id) }
          .to increment_yabeda_counter(Yabeda.outbox.sent_counter).with_tags(name: "combined-outbox_item", owner: nil, partition: 0, type: :outbox, worker_version: 1).by(1)
          .and update_yabeda_gauge(Yabeda.outbox.last_sent_event_id).with_tags(name: "combined-outbox_item", owner: nil, partition: 0, type: :outbox, worker_version: 1)
          .and measure_yabeda_histogram(Yabeda.outbox.process_latency).with_tags(name: "combined-outbox_item", owner: nil, partition: 0, type: :outbox, worker_version: 1)
      end
    end

    context "when outbox item produce to transport unsuccessfully" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow(producer).to receive(:call).and_return(false)
      end

      it "returns error" do
        expect(result).not_to be_success
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "calls middleware" do
        result
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
      end

      it "tracks error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result.failure).to eq :transport_failure
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.error_counter).by(1)
      end

      context "when has one retry available" do
        let(:max_retries) { 1 }

        it "doesn't change status to failed" do
          expect(Sbmt::Outbox.error_tracker).not_to receive(:error)
          expect(Sbmt::Outbox.logger).to receive(:log_failure)
          result
          expect(dummy_middleware).to have_received(:call).with(outbox_item)
          expect(outbox_item.reload).to be_pending
          expect(outbox_item.errors_count).to eq 1
        end

        it "tracks Yabeda retry counter" do
          expect { result }.to increment_yabeda_counter(Yabeda.outbox.retry_counter).by(1)
        end
      end

      context "when retry process" do
        let!(:outbox_item) { create(:outbox_item, processed_at: Time.current) }

        it "doesn't track process_latency" do
          expect { result }.to measure_yabeda_histogram(Yabeda.outbox.retry_latency)
            .and not_measure_yabeda_histogram(Yabeda.outbox.process_latency)
        end
      end
    end

    context "when item processing raised exception" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow(producer).to receive(:call).and_raise("boom")
      end

      it "returns error" do
        expect(result).to be_failure
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "calls middleware" do
        result
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
      end

      it "tracks error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
          .with(/Failed processing outbox item with error: RuntimeError boom/, stacktrace: kind_of(String))
        expect(result.failure).to eq :transport_failure
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.error_counter).by(1)
      end

      context "when error persisting fails" do
        let(:redis) { RedisClient.new(url: ENV["REDIS_URL"]) }

        before do
          allow_any_instance_of(OutboxItem).to receive(:failed!).and_raise("boom")
        end

        it "returns error" do
          expect(result).to be_failure
        end

        it "logs failure" do
          expect(Sbmt::Outbox.error_tracker).to receive(:error)
          allow(Sbmt::Outbox.logger).to receive(:log_failure)
          expect(result.failure).to eq :transport_failure
          expect(Sbmt::Outbox.logger)
            .to have_received(:log_failure)
            .with(/Could not persist status of failed outbox item due to error: RuntimeError boom/, stacktrace: kind_of(String))
        end

        it "calls middleware" do
          result
          expect(dummy_middleware).to have_received(:call).with(outbox_item)
        end

        it "tracks Yabeda error counter" do
          expect { result }.to increment_yabeda_counter(Yabeda.outbox.error_counter).by(1)
        end

        context "when worker_version is 1" do
          let(:worker_version) { 1 }

          it "skips item state caching" do
            result
            data = redis.call("GET", "outbox:outbox_item:#{outbox_item.id}")
            expect(data).to be_nil
          end
        end

        context "when worker_version is 2" do
          let(:worker_version) { 2 }

          context "when there is no cached item state" do
            it "caches item state in redis" do
              result
              data = redis.call("GET", "outbox:outbox_item:#{outbox_item.id}")
              deserialized = JSON.parse(data)
              expect(deserialized["timestamp"]).to be_an_integer
              expect(deserialized).to include(
                "error_msg" => "RuntimeError boom",
                "errors_count" => 1,
                "version" => 1
              )
            end

            it "sets ttl for item state data" do
              result
              res = redis.call("EXPIRETIME", "outbox:outbox_item:#{outbox_item.id}")
              expect(res).to be > 0
            end
          end

          context "when there is cached item state with greater errors_count" do
            before do
              data = Sbmt::Outbox::V2::RedisItemMeta.new(errors_count: 2, error_msg: "Some previous error")
              redis.call("SET", "outbox:outbox_item:#{outbox_item.id}", data.to_s)
            end

            it "caches item state in redis based on cached errors_count" do
              result
              data = redis.call("GET", "outbox:outbox_item:#{outbox_item.id}")
              deserialized = JSON.parse(data)
              expect(deserialized["timestamp"]).to be_an_integer
              expect(deserialized).to include(
                "error_msg" => "RuntimeError boom",
                "errors_count" => 3,
                "version" => 1
              )
            end

            it "sets ttl for item state data" do
              result
              res = redis.call("EXPIRETIME", "outbox:outbox_item:#{outbox_item.id}")
              expect(res).to be > 0
            end
          end

          context "when there is cached item state with le/eq errors_count" do
            before do
              data = Sbmt::Outbox::V2::RedisItemMeta.new(errors_count: 0, error_msg: "Some previous error")
              redis.call("SET", "outbox:outbox_item:#{outbox_item.id}", data.to_s)
            end

            it "caches item state in redis based on db errors_count" do
              result
              data = redis.call("GET", "outbox:outbox_item:#{outbox_item.id}")
              deserialized = JSON.parse(data)
              expect(deserialized["timestamp"]).to be_an_integer
              expect(deserialized).to include(
                "error_msg" => "RuntimeError boom",
                "errors_count" => 1,
                "version" => 1
              )
            end
          end
        end
      end
    end

    context "when item processing returning failure" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow(producer).to receive(:call)
          .and_return(Dry::Monads::Result::Failure.new("some error"))
      end

      it "returns error" do
        expect(result).to be_failure
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "calls middleware" do
        result
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end
    end

    context "when outbox item has many transports" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:transports).and_return([producer, HttpOrderSender])
      end

      it "returns success" do
        expect(result).to be_success
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
        expect(outbox_item.reload).to be_delivered
      end
    end

    context "when outbox item has custom payload builder" do
      let!(:outbox_item) { create(:outbox_item) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:payload_builder).and_return(PayloadRenderer)
      end

      it "returns success" do
        expect(producer).to receive(:call).with(outbox_item, "custom-payload").and_return(true)

        expect(result).to be_success
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
        expect(outbox_item.reload).to be_delivered
      end
    end

    context "when checking retry strategies" do
      let!(:outbox_item) { create(:outbox_item) }
      let(:max_retries) { 1 }

      before do
        allow(producer).to receive(:call).and_return(false)
      end

      it "doesn't change status to failed" do
        expect { result }.to change { outbox_item.reload.processed_at }
        expect(outbox_item).to be_pending
      end

      it "calls middleware" do
        result
        expect(dummy_middleware).to have_received(:call).with(outbox_item)
      end

      it "increments errors count" do
        expect { result }.to change { outbox_item.reload.errors_count }.from(0).to(1)
      end

      context "with the next processing time is greater than the current time" do
        let!(:outbox_item) do
          create(:outbox_item, processed_at: 1.hour.from_now)
        end

        it "doesn't increment errors count" do
          expect { result }.not_to change { outbox_item.reload.errors_count }
        end

        it "skips processing" do
          expect(result.failure).to eq :skip_processing
        end

        it "does not call middleware" do
          result
          expect(dummy_middleware).not_to have_received(:call)
        end
      end

      context "with the next processing time is less than the current time" do
        let!(:outbox_item) do
          create(:outbox_item, processed_at: 1.hour.ago)
        end

        it "increments errors count" do
          expect { result }.to change { outbox_item.reload.errors_count }.from(0).to(1)
        end

        it "processes with transport failure" do
          expect(result.failure).to eq :transport_failure
        end

        it "calls middleware" do
          result
          expect(dummy_middleware).to have_received(:call).with(outbox_item)
        end
      end

      context "when retry strategy discards item" do
        let!(:outbox_item) do
          create(:outbox_item, processed_at: 1.hour.ago)
        end

        let!(:outbox_item_2) do
          create(:outbox_item, status: :delivered, event_key: outbox_item.event_key)
        end

        it "discards processing" do
          expect(result.failure).to eq :discard_item
          expect(outbox_item.reload).to be_discarded
        end

        it "does not call middleware" do
          result
          expect(dummy_middleware).not_to have_received(:call)
        end
      end

      context "when retry strategy returns unknown error" do
        let!(:outbox_item) do
          create(:outbox_item, processed_at: 1.hour.ago)
        end

        before do
          allow_any_instance_of(OutboxItem).to receive(:event_key).and_return(nil)
        end

        it "fails" do
          expect(result.failure).to eq :retry_strategy_failure
          expect(outbox_item.reload).to be_pending
        end

        it "does not call middleware" do
          result
          expect(dummy_middleware).not_to have_received(:call)
        end
      end
    end
  end
end
