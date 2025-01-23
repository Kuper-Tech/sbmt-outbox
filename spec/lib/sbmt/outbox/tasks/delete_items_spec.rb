# frozen_string_literal: true

describe "rake outbox:delete_items" do
  subject(:task) { Rake::Task["outbox:delete_items"] }

  let(:klass) { "OutboxItem" }
  let(:status) { 1 }

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

    it "deletes records matching the given status" do
      expect {
        task.invoke(klass, status)
      }.to change(OutboxItem, :count).by(-1)

      expect(Rails.logger).to have_received(:info).with(/Batch items deleted: 1/)
      expect(Rails.logger).to have_received(:info).with(/Total items deleted: 1/)
    end
  end

  context "when filtering records by time range" do
    let(:start_time) { 7.hours.ago }
    let(:end_time) { 5.hours.ago }

    it "deletes records within the specified time range" do
      expect {
        task.invoke(klass, status, start_time, end_time)
      }.to change(OutboxItem, :count).by(-1)

      expect(Rails.logger).to have_received(:info).with(/Batch items deleted: 1/)
      expect(Rails.logger).to have_received(:info).with(/Total items deleted: 1/)
    end
  end

  context "when required parameters are missing" do
    it "raises an error" do
      expect {
        task.invoke(nil, status)
      }.to raise_error("Error: Class and status must be specified. Example: rake outbox:delete_items[OutboxItem,1]")

      expect(Rails.logger).not_to have_received(:info)
    end
  end
end
