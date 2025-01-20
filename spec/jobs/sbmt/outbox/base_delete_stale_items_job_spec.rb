# frozen_string_literal: true

describe Sbmt::Outbox::BaseDeleteStaleItemsJob do
  let(:job_class) do
    Class.new(described_class) do
      class << self
        def item_classes
          [OutboxItem]
        end
      end
    end
  end

  let!(:item_delivered) { create(:outbox_item, created_at: created_at, status: :delivered) }
  let!(:item_failed) { create(:outbox_item, created_at: created_at, status: :failed) }
  let(:created_at) { 1.month.ago }

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { job_class.enqueue }.to have_enqueued_job(job_class).with("OutboxItem")
    end
  end

  describe "#perform" do
    context "when all items exceed retention periods" do
      it "deletes items and tracks metrics" do
        expect { job_class.perform_now("OutboxItem") }
          .to change(OutboxItem, :count).by(-2)
          .and increment_yabeda_counter(Yabeda.outbox.deleted_counter).with_tags(box_name: "outbox_item", box_type: :outbox).by(2)
          .and measure_yabeda_histogram(Yabeda.outbox.delete_latency).with_tags(box_name: "outbox_item", box_type: :outbox)
      end
    end

    context "when items do not exceed the minimum retention period" do
      let(:created_at) { 6.hours.ago }

      it "does not delete items below the retention period but deletes others and tracks metrics" do
        expect { job_class.perform_now("OutboxItem") }
          .to change(OutboxItem, :count).by(-1)
          .and increment_yabeda_counter(Yabeda.outbox.deleted_counter).with_tags(box_name: "outbox_item", box_type: :outbox).by(1)
          .and measure_yabeda_histogram(Yabeda.outbox.delete_latency).with_tags(box_name: "outbox_item", box_type: :outbox)
      end
    end

    context "when retention period is invalid" do
      before do
        allow(OutboxItem.config).to receive_messages(retention: 6.hours, min_retention_period: 1.day)
      end

      it "raises an error" do
        expect { job_class.perform_now("OutboxItem") }
          .to raise_error("Retention period for outbox_item must be longer than 1 day")
      end
    end
  end
end
