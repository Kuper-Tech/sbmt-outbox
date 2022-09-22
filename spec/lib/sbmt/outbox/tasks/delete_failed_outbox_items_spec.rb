# frozen_string_literal: true

describe "rake outbox:delete_failed_items" do
  subject(:task) { Rake::Task["outbox:delete_failed_items"] }

  let!(:outbox_item_a) { Fabricate(:outbox_item, status: :failed, errors_count: 1) }
  let!(:outbox_item_b) { Fabricate(:outbox_item, status: :failed, errors_count: 1) }
  let!(:outbox_item_c) { Fabricate(:outbox_item, status: :delivered, errors_count: 0) }

  before do
    task.reenable
  end

  it "deletes all failed items" do
    expect { task.invoke("OutboxItem") }
      .to change(OutboxItem.all, :count).from(3).to(1)
  end

  context "when deleting specific item" do
    it "deletes that item only" do
      expect { task.invoke("OutboxItem", outbox_item_b.id) }
        .to change(OutboxItem.all, :count).from(3).to(2)
    end
  end
end
