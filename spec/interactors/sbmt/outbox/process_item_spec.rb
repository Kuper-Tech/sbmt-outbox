# frozen_string_literal: true

RSpec.describe Sbmt::Outbox::ProcessItem do
  describe "#call" do
    subject(:result) { described_class.call(OutboxItem, outbox_item.id, timeout: timeout) }

    let(:event_name) { "order_created" }
    let(:timeout) { 1 }
    let(:max_retries) { 0 }
    let(:exponential_retry_interval) { false }

    before do
      allow_any_instance_of(OrderCreatedProducer).to receive(:publish).and_return(true)
      allow(OutboxItem).to receive(:max_retries).and_return(max_retries)
      allow(OutboxItem).to receive(:exponential_retry_interval).and_return(exponential_retry_interval)
    end

    context "when outbox item is not found in db" do
      let(:outbox_item) { OpenStruct.new(id: 1, options: {}) }

      it "returns error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result).not_to be_success
        expect(result.failure).to match(/not found/)
      end
    end

    context "when outbox item is not in pending state" do
      let(:outbox_item) do
        Fabricate(
          :outbox_item,
          event_name: event_name,
          status: Sbmt::Outbox::Item.statuses[:failed]
        )
      end

      it "returns error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result).not_to be_success
        expect(result.failure).to match(/not found/)
      end
    end

    context "when there is no producer for defined event_name" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

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

      it "tracks error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)

        expect(result.failure).to match(/missing transports/)
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end
    end

    context "when outbox item produce to kafka successfully" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      it "returns success" do
        expect(Sbmt::Outbox.error_tracker).not_to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_success)
        expect(result).to be_success
      end

      it "removes outbox item" do
        expect { result }.to change(OutboxItem, :count).by(-1)
      end

      it "tracks Yabeda sent counter and last_sent_event_id" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.sent_counter)
          .and update_yabeda_gauge(Yabeda.outbox.last_sent_event_id)

        result
      end
    end

    context "when outbox item produce to kafka unsuccessfully" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow_any_instance_of(OrderCreatedProducer).to receive(:publish).and_return(false)
      end

      it "returns error" do
        expect(result).not_to be_success
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "tracks error" do
        expect(Sbmt::Outbox.error_tracker).to receive(:error)
        expect(Sbmt::Outbox.logger).to receive(:log_failure)
        expect(result.failure).to match(/transport OrderCreatedProducer returned false/)
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end

      it "tracks Yabeda error counter" do
        expect { result }.to increment_yabeda_counter(Yabeda.outbox.error_counter)

        result
      end

      context "when has one retry available" do
        let(:max_retries) { 1 }

        it "doesn't change status to failed" do
          expect(Sbmt::Outbox.error_tracker).not_to receive(:error)
          expect(Sbmt::Outbox.logger).to receive(:log_failure)
          result
          expect(outbox_item.reload).to be_pending
          expect(outbox_item.errors_count).to eq 1
        end

        it "tracks Yabeda retry counter" do
          expect { result }.to increment_yabeda_counter(Yabeda.outbox.retry_counter)

          result
        end
      end
    end

    context "when there is timeout error when publishing to kafka" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow_any_instance_of(OrderCreatedProducer).to receive(:publish) do
          sleep 2
          false
        end
      end

      it "returns error" do
        expect { result }.not_to change(OutboxItem, :count)
        expect(result).not_to be_success
        expect(outbox_item.reload).to be_failed
        expect(result.failure).to match(/execution expired/)
      end
    end

    context "when outbox item has many transports" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:transports).and_return([OrderCreatedProducer, HttpOrderSender])
      end

      it "returns success" do
        expect(result).to be_success
      end

      it "removes outbox item" do
        expect { result }.to change(OutboxItem, :count).by(-1)
      end
    end

    context "when outbox item has custom payload builder" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:payload_builder).and_return(PayloadRenderer)
      end

      it "returns success" do
        expect(OrderCreatedProducer).to receive(:call).with(outbox_item, "custom-payload").and_return(true)

        expect(result).to be_success
      end

      it "removes outbox item" do
        expect { result }.to change(OutboxItem, :count).by(-1)
      end
    end

    context "when outbox item has custom retry strategy" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow_any_instance_of(OutboxItem).to receive(:retry_strategy).and_return(RetryStrategy)
      end

      it "returns success" do
        expect(RetryStrategy).to receive(:call).with(outbox_item).and_return(true)

        expect(result).to be_success
      end

      it "removes outbox item" do
        expect { result }.to change(OutboxItem, :count).by(-1)
      end
    end

    context "when exponential_retry_interval enabled" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }
      let(:exponential_retry_interval) { true }

      before do
        allow_any_instance_of(OrderCreatedProducer).to receive(:publish).and_return(false)
      end

      it "changes status to failed" do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "updates processed_at attribute" do
        expect { result }.to change { outbox_item.reload.processed_at }
      end

      context "when has one retry available" do
        let(:max_retries) { 1 }

        it "doesn't change status to failed" do
          result
          expect(outbox_item.reload).to be_pending
        end

        it "increment errors count" do
          expect { result }.to change { outbox_item.reload.errors_count }.from(0).to(1)
        end

        context "with the next processing time is greater than the current time" do
          let!(:outbox_item) do
            Fabricate(:outbox_item, event_name: event_name, processed_at: 1.hour.from_now)
          end

          it "doesn't increment errors count" do
            expect { result }.not_to change { outbox_item.reload.errors_count }
          end

          it "outbox item processing skip" do
            expect(result.failure).to match(/Skip processing/)
          end
        end

        context "with the next processing time is less than the current time" do
          let!(:outbox_item) do
            Fabricate(:outbox_item, event_name: event_name, processed_at: 1.hour.ago)
          end

          it "increment errors count" do
            expect { result }.to change { outbox_item.reload.errors_count }.from(0).to(1)
          end

          it "outbox item processing continues" do
            expect(result.failure).not_to match(/Skip processing/)
          end
        end
      end
    end
  end
end
