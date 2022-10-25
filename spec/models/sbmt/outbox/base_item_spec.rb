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
end
