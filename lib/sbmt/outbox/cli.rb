# frozen_string_literal: true

require "thor"
require "sbmt/outbox/ascii_art"

module Sbmt
  module Outbox
    class CLI < Thor
      def self.exit_on_failure?
        true
      end

      default_command :start

      desc "start", "Start outbox worker"
      option :box,
        aliases: "-b",
        repeatable: true,
        desc: "Outbox/Inbox processors to start in format foo_name:1,2,n bar_name:1,2,n"
      option :concurrency,
        aliases: "-c",
        type: :numeric,
        desc: "Number of threads (processor)"
      option :poll_concurrency,
        aliases: "-p",
        type: :numeric,
        desc: "Number of poller partitions"
      option :poll_threads,
        aliases: "-n",
        type: :numeric,
        default: 1,
        desc: "Number of threads (poller)"
      option :poll_tactic,
        aliases: "-t",
        type: :string,
        desc: "Poll tactic: [default, low-priority, aggressive]"
      option :version,
        aliases: "-w",
        type: :numeric,
        default: 2,
        desc: "Worker version: [1 | 2]"
      def start
        version = options[:version]

        load_environment(version)

        worker = if version == 1
          Sbmt::Outbox::V1::Worker.new(
            boxes: format_boxes(options[:box]),
            concurrency: options[:concurrency] || 10
          )
        elsif version == 2
          Sbmt::Outbox::V2::Worker.new(
            boxes: format_boxes(options[:box]),
            poll_tactic: options[:poll_tactic],
            poller_threads_count: options[:poll_threads],
            poller_partitions_count: options[:poll_concurrency],
            processor_concurrency: options[:concurrency] || 4
          )
        else
          raise "Worker version #{version} is invalid, available versions: 1|2"
        end

        Sbmt::Outbox.current_worker = worker

        watch_signals(worker)

        $stdout.puts AsciiArt.logo
        $stdout.puts "Outbox/Inbox worker has been started"
        $stdout.puts "Version: #{VERSION}"
        $stdout.puts "Starting probes..."
        Sbmt::Outbox::Probes::Probe.run_probes

        worker.start
      end

      private

      def load_environment(version)
        load(lookup_outboxfile)

        require "sbmt/outbox"
        require "sbmt/outbox/v1/worker" if version == 1
        require "sbmt/outbox/v2/worker" if version == 2
      end

      def lookup_outboxfile
        file_path = ENV["OUTBOXFILE"] || "#{Dir.pwd}/Outboxfile"

        raise "Cannot locate Outboxfile at #{file_path}" unless File.exist?(file_path)

        file_path
      end

      def format_boxes(val)
        if val.nil?
          fetch_all_boxes
        else
          extract_boxes(val)
        end
      end

      def fetch_all_boxes
        Outbox.outbox_item_classes + Outbox.inbox_item_classes
      end

      def extract_boxes(boxes)
        boxes.map do |name, acc|
          item_class = Sbmt::Outbox.item_classes_by_name[name]
          raise "Cannot locate box #{name}" unless item_class
          item_class
        end
      end

      def watch_signals(worker)
        # ctrl+c
        Signal.trap("INT") do
          $stdout.puts AsciiArt.shutdown
          $stdout.puts "Going to shut down..."
          worker.stop
        end

        # normal kill with number 15
        Signal.trap("TERM") do
          $stdout.puts AsciiArt.shutdown
          $stdout.puts "Going to shut down..."
          worker.stop
        end
      end
    end
  end
end
