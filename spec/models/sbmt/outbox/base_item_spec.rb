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

    it "returns valid options" do
      def outbox_item.extra_options
        {
          foo: true,
          bar: true
        }
      end

      outbox_item.options = {bar: false}

      expect(outbox_item.options).to include(:headers, :foo, :bar)
      expect(outbox_item.options[:bar]).to be false
    end

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
      expect(outbox_item.errors_count).to eq(1)

      error = StandardError.new("another-error")
      outbox_item.add_error(error)
      outbox_item.save!
      outbox_item.reload

      expect(outbox_item.error_log).to include("another-error")
      expect(outbox_item.error_log).not_to include("test-error")
      expect(outbox_item.errors_count).to eq(2)
    end
  end

  describe "#partition" do
    let(:outbox_item) { Fabricate.build(:outbox_item, bucket: 3) }

    it "returns valid partition" do
      expect(outbox_item.partition).to eq 1
    end
  end

  describe ".partition_buckets" do
    it "returns buckets of partitions" do
      expect(OutboxItem.partition_buckets).to eq(0 => [0, 2], 1 => [1, 3])
    end

    context "when the number of partitions is not a multiple of the number of buckets" do
      before do
        if OutboxItem.instance_variable_defined?(:@partition_buckets)
          OutboxItem.remove_instance_variable(:@partition_buckets)
        end

        allow(OutboxItem.config).to receive_messages(partition_size: 2, bucket_size: 5)
      end

      after do
        OutboxItem.remove_instance_variable(:@partition_buckets)
      end

      it "returns buckets of partitions" do
        expect(OutboxItem.partition_buckets).to eq(0 => [0, 2, 4], 1 => [1, 3])
      end
    end
  end

  describe ".bucket_partitions" do
    it "returns buckets of partitions" do
      expect(OutboxItem.bucket_partitions).to eq(0 => 0, 1 => 1, 2 => 0, 3 => 1)
    end
  end

  describe "#transports" do
    context "when transport was built by factory" do
      let(:outbox_item) { Fabricate.build(:outbox_item) }

      it "returns disposable transport" do
        # init transports for the first time
        outbox_item.transports

        transport = instance_double(Producer)
        expect(Producer)
          .to receive(:new)
          .with(topic: "outbox_item_topic", kafka: {"required_acks" => -1}).and_return(transport)
        expect(transport).to receive(:call)
        expect(outbox_item.transports.size).to eq 1
        outbox_item.transports.first.call(outbox_item, "payload")
      end
    end

    context "when transport was built by name" do
      let(:inbox_item) { Fabricate.build(:inbox_item) }

      it "returns valid transports" do
        # init transports for the first time
        inbox_item.transports

        expect(ImportOrder).not_to receive(:new)
        expect(inbox_item.transports.first).to be_a(ImportOrder)
        expect(inbox_item.transports.first.source).to eq "kafka_consumer"
        inbox_item.transports.first.call(inbox_item, "payload")
      end
    end

    context "when transports were selected by event name" do
      let(:outbox_item) { Fabricate.build(:combined_outbox_item, event_name: "orders_completed") }

      it "returns disposable transport" do
        # init transports for the first time
        outbox_item.transports

        transport = instance_double(Producer)
        expect(Producer)
          .to receive(:new)
          .with(topic: "orders_completed_topic", kafka: {}).and_return(transport)
        expect(transport).to receive(:call)
        expect(outbox_item.transports.size).to eq 1
        outbox_item.transports.first.call(outbox_item, "payload")
      end
    end
  end
end
