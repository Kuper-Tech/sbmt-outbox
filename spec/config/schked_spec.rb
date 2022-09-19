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

  describe "Sbmt::Outbox::ProcessItemsJob" do
    let(:job) { worker.job("Sbmt::Outbox::ProcessItemsJob") }
    let(:start_time) { Time.zone.local(2008, 9, 1, 2, 30, 10) }
    let(:next_ten_sec) { Time.zone.local(2008, 9, 1, 2, 30, 20) }

    it "executes every 10 sec" do
      expect(job.next_time.to_local_time).to eq(next_ten_sec)
    end

    it "enqueues job" do
      expect { job.call(false) }.to change { Sbmt::Outbox::ProcessItemsJob.jobs.size }.by(1)
    end
  end

  describe "Sbmt::Outbox::DeleteStaleItemsJob" do
    let(:job) { worker.job("Sbmt::Outbox::DeleteStaleItemsJob") }
    let(:start_time) { Time.zone.local(2008, 9, 1, 2, 30, 10) }
    let(:next_ten_sec) { Time.zone.local(2008, 9, 1, 3, 30, 10) }

    it "executes every 1 hour" do
      expect(job.next_time.to_local_time).to eq(next_ten_sec)
    end

    it "enqueues job" do
      expect { job.call(false) }.to change { Sbmt::Outbox::DeleteStaleItemsJob.jobs.size }.by(1)
    end
  end
end
