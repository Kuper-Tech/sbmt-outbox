# frozen_string_literal: true

describe Sbmt::Outbox::CreateOutboxItem do
  subject(:result) { described_class.call(Combined::OutboxItem, attributes: attributes) }

  let(:attributes) do
    {
      payload: "test",
      event_key: 10,
      event_name: "order_created"
    }
  end

  it "creates a record" do
    expect { result }.to change(Combined::OutboxItem, :count).by(1)
    expect(result).to be_success
    expect(result.value!).to have_attributes(bucket: 1)
  end

  it "tracks Yabeda metrics" do
    expect { result }
      .to update_yabeda_gauge(Yabeda.outbox.last_stored_event_id).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 1)
      .and increment_yabeda_counter(Yabeda.outbox.created_counter).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 1)
  end

  context "when got errors" do
    before do
      attributes.delete(:event_key)
    end

    it "does not track Yabeda metrics" do
      expect { result }
        .to not_update_yabeda_gauge(Yabeda.outbox.last_stored_event_id)
        .and not_increment_yabeda_counter(Yabeda.outbox.created_counter)
    end

    it "returns errors" do
      expect { result }.not_to change(Combined::OutboxItem, :count)
      expect(result).not_to be_success
    end
  end

  context "when partition by custom key" do
    subject(:result) { described_class.call(Combined::OutboxItem, attributes: attributes, partition_by: partition_by) }

    let(:partition_by) { 9 }

    it "creates a record" do
      expect { result }.to change(Combined::OutboxItem, :count).by(1)
      expect(result).to be_success
      expect(result.value!).to have_attributes(bucket: 3)
    end
  end
end
