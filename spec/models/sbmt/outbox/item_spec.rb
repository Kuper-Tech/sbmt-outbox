# frozen_string_literal: true

describe Sbmt::Outbox::Item do
  describe "#max_retries_exceeded?" do
    let(:outbox_item) { Fabricate(:outbox_item) }

    context "when reading from yaml config" do
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
end
