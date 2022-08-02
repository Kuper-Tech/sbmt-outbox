# frozen_string_literal: true

RSpec.describe Sbmt::Outbox::ProcessItem do
  describe "#call" do
    subject(:result) { described_class.call(OutboxItem, outbox_item.id, timeout: timeout) }

    let(:event_name) { "order_created" }
    let(:timeout) { 1 }

    before do
      allow_any_instance_of(OrderCreatedProducer).to receive(:publish).and_return(true)
    end

    context "when outbox item is not found in db" do
      let(:outbox_item) { OpenStruct.new(id: 1, options: {}) }

      it "returns error" do
        expect(result).not_to be_success
        expect(result.failure).to eq("OutboxItem#{outbox_item.id} not found")
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
        expect(result).not_to be_success
        expect(result.failure).to eq("OutboxItem#{outbox_item.id} not found")
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

      it 'changes status to "failed"' do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "tracks error" do
        expect(result.failure).to eq("missing transports for OutboxItem##{outbox_item.id}")
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end
    end

    context "when outbox item produce to kafka successfully" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      it "returns success" do
        expect(result).to be_success
      end

      it "removes outbox item" do
        expect { result }.to change(OutboxItem, :count).by(-1)
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

      it 'changes status to "failed"' do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "tracks error" do
        error_message = "Export failed for OutboxItem##{outbox_item.id} with error: " \
          "Transport OrderCreatedProducer returned false"
        expect(result.failure).to eq(error_message)
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
      end
    end

    context "when there is timeout error when publishing to kafka" do
      let!(:outbox_item) { Fabricate(:outbox_item, event_name: event_name) }

      before do
        allow(Timeout)
          .to(receive(:timeout))
          .with(timeout, described_class::ProcessItemError)
          .and_raise(described_class::ProcessItemError, "timeout")
      end

      it "returns error" do
        expect(result).not_to be_success
      end

      it 'changes status to "failed"' do
        result
        expect(outbox_item.reload).to be_failed
      end

      it "tracks error" do
        expect(result.failure).to eq("timeout")
      end

      it "does not remove outbox item" do
        expect { result }.not_to change(OutboxItem, :count)
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
  end
end
