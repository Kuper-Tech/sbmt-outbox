# frozen_string_literal: true

require "rails_helper"

describe Schked do
  let(:worker) { described_class.worker.tap(&:pause) }

  let(:time_zone) { "UTC" }

  around do |ex|
    Time.use_zone(time_zone) do
      travel_to(start_time, &ex)
    end
  end

  describe "Sbmt::Outbox::DeleteStaleOutboxItemsJob" do
    let(:job) { worker.job("Sbmt::Outbox::DeleteStaleOutboxItemsJob") }
    let(:start_time) { Time.zone.local(2008, 9, 1, 2, 30, 10) }
    let(:next_ten_mins) { Time.zone.local(2008, 9, 1, 2, 40, 10) }

    it "executes every 10 minutes" do
      expect(job.next_time.to_local_time).to eq(next_ten_mins)
    end

    it "enqueues job" do
      expect { job.call(false) }.to have_enqueued_job(Sbmt::Outbox::DeleteStaleOutboxItemsJob)
    end
  end

  describe "Sbmt::Outbox::DeleteStaleInboxItemsJob" do
    let(:job) { worker.job("Sbmt::Outbox::DeleteStaleInboxItemsJob") }
    let(:start_time) { Time.zone.local(2008, 9, 1, 2, 30, 10) }
    let(:next_ten_mins) { Time.zone.local(2008, 9, 1, 2, 40, 10) }

    it "executes every 10 minutes" do
      expect(job.next_time.to_local_time).to eq(next_ten_mins)
    end

    it "enqueues job" do
      expect { job.call(false) }.to have_enqueued_job(Sbmt::Outbox::DeleteStaleInboxItemsJob)
    end
  end
end
