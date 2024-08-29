# frozen_string_literal: true

describe Sbmt::Outbox::CreateOutboxBatch do
  subject(:result) { described_class.call(Combined::OutboxItem, batch_attributes: batch_attributes) }

  let(:batch_attributes) do
    [
      {
        payload: "test",
        event_key: 10,
        event_name: "order_created"
      },
      {
        payload: "test2",
        event_key: 5,
        event_name: "order_created"
      }
    ]
  end

  it "creates records" do
    expect { result }.to change(Combined::OutboxItem, :count).by(2)
    expect(result).to be_success
    expect(result.value!).to match_array(Combined::OutboxItem.ids)
  end

  it "tracks Yabeda metrics" do
    expect { result }
      .to update_yabeda_gauge(Yabeda.outbox.last_stored_event_id).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 1).with(Combined::OutboxItem.ids.first)
      .and increment_yabeda_counter(Yabeda.outbox.created_counter).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 1).by(Combined::OutboxItem.ids.first)
      .and update_yabeda_gauge(Yabeda.outbox.last_stored_event_id).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 0).with(Combined::OutboxItem.ids.last)
      .and increment_yabeda_counter(Yabeda.outbox.created_counter).with_tags(name: "combined-outbox_item", type: :outbox, owner: nil, partition: 0).by(Combined::OutboxItem.ids.last)
  end

  context "when got errors" do
    let(:batch_attributes) do
      [
        {
          payload: "test",
          event_name: "order_created"
        },
        {
          payload: "test2",
          event_name: "order_created"
        }
      ]
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
    let(:batch_attributes) do
      [
        {
          payload: "test",
          event_key: 10,
          event_name: "order_created"
        },
        {
          payload: "test2",
          event_key: 11,
          event_name: "order_created",
          partition_by: 6
        }
      ]
    end

    it "creates a record" do
      expect { result }.to change(Combined::OutboxItem, :count).by(2)
      expect(result).to be_success

      outbox_items = Combined::OutboxItem.pluck(:id, :bucket)
      expect(result.value!).to match_array(outbox_items.map(&:first))
      expect(outbox_items.map(&:last)).to contain_exactly(0, 1)
    end
  end
end
