# frozen_string_literal: true

require "ostruct"

describe Sbmt::Outbox::ProcessItem do
  describe "#call" do
    subject(:result) { described_class.call(OutboxItem, outbox_item.id) }

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
          .with(/Failed processing outbox item with error: not found/, backtrace: nil)
        expect(result).not_to be_success
        expect(dummy_middleware).not_to have_received(:call)
        expect(result.failure).to eq :not_found
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.fetch_error_counter).by(1)
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
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result).not_to be_success
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
          expect { result }.not_to measure_yabeda_histogram(Yabeda.outbox.process_latency)
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
          .with(/Failed processing outbox item with error: RuntimeError boom/, backtrace: kind_of(String))
        expect(result.failure).to eq :transport_failure
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.error_counter).by(1)
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
