# frozen_string_literal: true

describe Sbmt::Outbox::BaseItem do
  describe "#max_retries_exceeded?" do
    let(:outbox_item) { Fabricate(:outbox_item) }

    before do
      allow(outbox_item.config).to receive(:max_retries).and_return(1)
    end

    it "has available retries" do
      expect(outbox_item).not_to be_max_retries_exceeded
    end

    context "when item was retried" do
      let(:outbox_item) { Fabricate(:outbox_item, errors_count: 2) }

      it "has not available retries" do
        expect(outbox_item).to be_max_retries_exceeded
      end
    end
  end

  describe "#options" do
    let(:outbox_item) { Fabricate(:outbox_item) }
    let(:dispatched_at_header_name) { Sbmt::Outbox::OutboxItem::DISPATCH_TIME_HEADER_NAME }

    it "has 'Dispatched-At' header" do
      expect(outbox_item.options[:headers].has_key?(dispatched_at_header_name)).to be(true)
    end
  end

  describe "#add_error" do
    let(:outbox_item) { Fabricate(:outbox_item) }

    it "saves exception message to record" do
      error = StandardError.new("test-error")
      outbox_item.add_error(error)
      outbox_item.save!
      outbox_item.reload

      expect(outbox_item.error_log).to include("test-error")

      error = StandardError.new("another-error")
      outbox_item.add_error(error)
      outbox_item.save!
      outbox_item.reload

      expect(outbox_item.error_log).to include("another-error")
    end
  end

  describe "#partition" do
    let(:outbox_item) { Fabricate.build(:outbox_item, bucket: 3) }

    it "returns valid partition" do
      expect(outbox_item.partition).to eq 1
    end

    context "when bucket out of bucket size" do
      let(:outbox_item) { Fabricate.build(:outbox_item, bucket: 999) }

      it "returns first partition" do
        expect(outbox_item.partition).to eq 0
      end
    end
  end

  describe ".partition_buckets" do
    before do
      allow(OutboxItem.config).to receive(:bucket_size).and_return(4)
      allow(OutboxItem.config).to receive(:partition_size).and_return(2)
    end

    it "returns buckets of partitions" do
      expect(OutboxItem.partition_buckets).to eq(0 => [0, 2], 1 => [1, 3])
    end
  end

  describe ".bucket_partitions" do
    before do
      allow(OutboxItem.config).to receive(:bucket_size).and_return(4)
      allow(OutboxItem.config).to receive(:partition_size).and_return(2)
    end

    it "returns buckets of partitions" do
      expect(OutboxItem.bucket_partitions).to eq(0 => 0, 1 => 1, 2 => 0, 3 => 1)
    end
  end
end
