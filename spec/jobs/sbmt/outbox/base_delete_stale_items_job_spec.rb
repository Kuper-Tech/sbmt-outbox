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

  let!(:item_delivered) { create(:outbox_item, created_at: created_at, status: 2) }
  let!(:item_failed) { create(:outbox_item, created_at: created_at, status: 1) }
  let(:created_at) { 1.month.ago }

  before do
    stub_const("Sbmt::Outbox::BaseDeleteStaleItemsJob::BATCH_SIZE", 1)
  end

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { job_class.enqueue }.to have_enqueued_job(job_class).with("OutboxItem")
    end
  end

  it "deletes items with status 2 and old items with status 1" do
    expect { job_class.perform_now("OutboxItem") }
      .to change(OutboxItem, :count).by(-2)
  end

  context "when an element with status 1 does not retention" do
    let(:created_at) { 6.hours.ago }

    it "doesn't delete item with status 1 but deletes item with status 2" do
      expect { job_class.perform_now("OutboxItem") }
        .to change(OutboxItem, :count).by(-1)
    end
  end
end
