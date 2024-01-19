# frozen_string_literal: true

describe "rake outbox:retry_failed_items" do
  subject(:task) { Rake::Task["outbox:retry_failed_items"] }

  let!(:outbox_item_a) { create(:outbox_item, status: :failed, errors_count: 1) }
  let!(:outbox_item_b) { create(:outbox_item, status: :failed, errors_count: 1) }
  let!(:outbox_item_c) { create(:outbox_item, status: :delivered, errors_count: 0) }

  before do
    task.reenable
  end

  # rubocop:disable RSpec/PendingWithoutReason
  it "sets pending state for all failed items" do
    expect { task.invoke("OutboxItem") }
      .to change(OutboxItem.pending, :count).from(0).to(2)
  end

  it "resets errors_count for all failed items" do
    expect { task.invoke("OutboxItem") }
      .to change(OutboxItem.where(errors_count: 0), :count).from(1).to(3)
  end

  context "when retring specific item" do
    it "sets pending state for that item only" do
      expect { task.invoke("OutboxItem", outbox_item_b.id) }
        .to change(OutboxItem.pending, :count).from(0).to(1)
    end

    it "resets errors_count for all failed items" do
      expect { task.invoke("OutboxItem", outbox_item_b.id) }
        .to change(OutboxItem.where(errors_count: 0), :count).from(1).to(2)
    end
  end
  # rubocop:enable RSpec/PendingWithoutReason
end
