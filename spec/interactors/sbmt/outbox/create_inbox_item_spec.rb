# frozen_string_literal: true

describe Sbmt::Outbox::CreateInboxItem do
  subject(:result) { described_class.call(InboxItem, attributes: attributes) }

  let(:attributes) do
    {
      event_name: "order_created",
      proto_payload: "test",
      event_key: 10,
      partition_key: 15
    }
  end

  it "creates a record" do
    expect { result }.to change(InboxItem, :count).by(1)
    expect(result).to be_success
  end

  it "tracks Yabeda metrics" do
    expect { result }.to update_yabeda_gauge(Yabeda.inbox.last_stored_event_id)
  end

  context "when got errors" do
    let(:attributes) { {} }

    it "does not track Yabeda metrics" do
      expect { result }.not_to update_yabeda_gauge(Yabeda.inbox.last_stored_event_id)
    end

    it "returns errors" do
      expect { result }.not_to change(InboxItem, :count)
      expect(result).not_to be_success
    end
  end
end
