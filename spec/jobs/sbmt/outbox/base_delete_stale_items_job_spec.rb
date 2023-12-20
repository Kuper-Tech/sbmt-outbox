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

  let!(:item) { Fabricate(:outbox_item, created_at: created_at) }
  let(:created_at) { 1.month.ago }

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { job_class.enqueue }.to have_enqueued_job(job_class).with("OutboxItem")
    end
  end

  it "deletes item" do
    expect { job_class.perform_now("OutboxItem") }
      .to change(OutboxItem, :count).by(-1)
  end

  context "when item is too yang" do
    let(:created_at) { 1.hour.ago }

    it "doesn't delete item" do
      expect { job_class.perform_now("OutboxItem") }
        .not_to change(OutboxItem, :count)
    end
  end
end
