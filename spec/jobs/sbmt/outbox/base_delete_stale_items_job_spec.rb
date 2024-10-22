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

  let!(:item) { create(:outbox_item, created_at: created_at) }
  let!(:item_2) { create(:outbox_item, created_at: created_at) }
  let(:created_at) { 1.month.ago }

  before do
    stub_const("Sbmt::Outbox::BaseDeleteStaleItemsJob::BATCH_SIZE", 1)
  end

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { job_class.enqueue }.to have_enqueued_job(job_class).with("OutboxItem")
    end
  end

  it "deletes item" do
    expect { job_class.perform_now("OutboxItem") }
      .to change(OutboxItem, :count).by(-2)
  end

  context "when item is too young" do
    let(:created_at) { 1.hour.ago }

    it "doesn't delete item" do
      expect { job_class.perform_now("OutboxItem") }
        .not_to change(OutboxItem, :count)
    end
  end
end
