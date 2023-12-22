# frozen_string_literal: true

describe Sbmt::Outbox::CreateOutboxItem do
  subject(:result) { described_class.call(OutboxItem, attributes: attributes) }

  let(:attributes) do
    {
      payload: "test",
      event_key: 10
    }
  end

  it "creates a record" do
    expect { result }.to change(OutboxItem, :count).by(1)
    expect(result).to be_success
    expect(result.value!).to have_attributes(bucket: 2)
  end

  it "tracks Yabeda metrics" do
    expect { result }.to update_yabeda_gauge(Yabeda.outbox.last_stored_event_id)
  end

  context "when got errors" do
    before do
      attributes.delete(:event_key)
    end

    it "does not track Yabeda metrics" do
      expect { result }.not_to update_yabeda_gauge(Yabeda.outbox.last_stored_event_id)
    end

    it "returns errors" do
      expect { result }.not_to change(OutboxItem, :count)
      expect(result).not_to be_success
    end
  end

  context "when partition by custom key" do
    subject(:result) { described_class.call(InboxItem, attributes: attributes, partition_by: partition_by) }

    let(:partition_by) { 9 }

    it "creates a record" do
      expect { result }.to change(InboxItem, :count).by(1)
      expect(result).to be_success
      expect(result.value!).to have_attributes(bucket: 1)
    end
  end
end
