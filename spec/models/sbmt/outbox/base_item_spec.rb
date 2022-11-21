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
end
