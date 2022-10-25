# frozen_string_literal: true

describe Sbmt::Outbox::BaseProcessItemsJob do
  let(:job_class) do
    Class.new(described_class) do
      class << self
        def item_classes
          [OutboxItem]
        end
      end
    end
  end

  let!(:item) { Fabricate(:outbox_item, event_name: "created_order") }

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { job_class.enqueue }.to change { job_class.jobs.size }.by(1)
      expect(job_class.jobs.last["args"]).to match_array(["OutboxItem", 0])
    end
  end

  it "calls interactor" do
    expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id)

    job_class.perform_async("OutboxItem")
    job_class.drain
  end

  it "skips failed items" do
    item.update!(status: OutboxItem.statuses[:failed])
    expect(Sbmt::Outbox::ProcessItem).not_to receive(:call)

    job_class.perform_async("OutboxItem")
    job_class.drain
  end

  context "when requeue timeout error" do
    let!(:item_2) { Fabricate(:outbox_item, event_name: "created_order") }
    let(:cutoff) { 1 }

    before do
      allow(Sbmt::Outbox.config.process_items)
        .to receive(:cutoff_timeout).and_return(cutoff)
    end

    it "processes only one item" do
      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id) do |_item_class, _id|
        sleep 1
      end

      expect(Sbmt::Outbox::ProcessItem).not_to receive(:call).with(OutboxItem, item_2.id)

      expect_any_instance_of(job_class).to receive(:requeue!)

      job_class.perform_async("OutboxItem")
      job_class.drain
    end
  end

  context "when general timeout error" do
    let!(:item_2) { Fabricate(:outbox_item, event_name: "created_order") }
    let(:cutoff) { 1 }
    let(:timeout) { 1 }

    before do
      allow(Sbmt::Outbox.config.process_items)
        .to receive(:general_timeout).and_return(timeout)

      allow(Sbmt::Outbox.config.process_items)
        .to receive(:cutoff_timeout).and_return(cutoff)
    end

    it "processes only one item" do
      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id) do |_item_class, _id|
        sleep 2
      end

      expect(Sbmt::Outbox::ProcessItem).not_to receive(:call).with(OutboxItem, item_2.id)

      expect_any_instance_of(job_class).not_to receive(:requeue!)

      job_class.perform_async("OutboxItem")
      job_class.drain
    end
  end

  context "when job expired" do
    before do
      allow(Sbmt::Outbox.config.process_items)
        .to receive(:queue_timeout).and_return(-1)
    end

    it "does nothing" do
      expect(Sbmt::Outbox::ProcessItem).not_to receive(:call)

      job_class.perform_async("OutboxItem")
      job_class.drain
    end
  end
end
