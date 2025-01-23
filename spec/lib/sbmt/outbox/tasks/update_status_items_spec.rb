# frozen_string_literal: true

describe "rake outbox:update_status_items" do
  subject(:task) { Rake::Task["outbox:update_status_items"] }

  let(:klass) { "OutboxItem" }
  let(:status) { 1 }
  let(:new_status) { 3 }

  let(:created_at_a) { 6.hours.ago }
  let(:created_at_b) { 8.hours.ago }
  let(:created_at_c) { 4.hours.ago }

  let!(:outbox_item_a) { create(:outbox_item, status: :failed, errors_count: 1, created_at: created_at_a) }
  let!(:outbox_item_b) { create(:outbox_item, status: :failed, errors_count: 1, created_at: created_at_b) }
  let!(:outbox_item_c) { create(:outbox_item, status: :delivered, errors_count: 0, created_at: created_at_c) }

  before do
    task.reenable
    allow(Rails.logger).to receive(:info)
  end

  context "when filtering records by status" do
    let(:created_at_a) { Time.zone.now }
    let(:created_at_b) { 6.hours.ago }
    let(:created_at_c) { Time.zone.now }

    it "updates records matching the given status" do
      expect {
        task.invoke(klass, status, new_status)
        outbox_item_a.reload
        outbox_item_b.reload
        outbox_item_c.reload
      }.to change(outbox_item_b, :status).from("failed").to("discarded")
        .and not_change { outbox_item_a.status }
        .and not_change { outbox_item_c.status }

      expect(Rails.logger).to have_received(:info).with(/Batch items updated: 1/)
      expect(Rails.logger).to have_received(:info).with(/Total items updated: 1/)
    end
  end

  context "when filtering records by time range" do
    let(:start_time) { 7.hours.ago }
    let(:end_time) { 5.hours.ago }

    it "updates records within the specified time range" do
      expect {
        task.invoke(klass, status, new_status, start_time, end_time)
        outbox_item_a.reload
        outbox_item_b.reload
        outbox_item_c.reload
      }.to change(outbox_item_a, :status).from("failed").to("discarded")
        .and not_change { outbox_item_b.status }
        .and not_change { outbox_item_c.status }

      expect(Rails.logger).to have_received(:info).with(/Batch items updated: 1/)
      expect(Rails.logger).to have_received(:info).with(/Total items updated: 1/)
    end
  end

  context "when required parameters are missing" do
    it "raises an error" do
      expect {
        task.invoke(nil, status, new_status)
      }.to raise_error("Error: Class, current status, and new status must be specified. Example: rake outbox:update_status_items[OutboxItem,0,3]")

      expect(Rails.logger).not_to have_received(:info)
    end
  end
end
