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
      option :boxes,
        aliases: "-b",
        type: :hash,
        repeatable: true,
        desc: "Outbox/Inbox processors to start in format foo_name:1,2,n bar_name:1,2,n"
      option :concurrency,
        aliases: "-c",
        type: :numeric,
        default: 10,
        desc: "Number of threads"
      def start
        load_environment

        worker = Sbmt::Outbox::Worker.new(
          boxes: format_boxes(options[:boxes]),
          concurrency: options[:concurrency]
        )

        Sbmt::Outbox.current_worker = worker

        watch_signals(worker)

        $stdout.puts AsciiArt.logo
        $stdout.puts "Outbox/Inbox worker has been started"
        $stdout.puts "Version: #{VERSION}"

        worker.start
      end

      private

      def load_environment
        load(lookup_outboxfile)

        require "sbmt/outbox"
        require "sbmt/outbox/worker"
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
        (Outbox.outbox_item_classes + Outbox.inbox_item_classes).index_with do |item_class|
          Range.new(1, item_class.config.partition_size).to_a
        end
      end

      def extract_boxes(boxes)
        boxes.each_with_object({}) do |(name, partitions), acc|
          key = Outbox.item_classes_by_name[name]
          raise "Cannot locate box #{name}" unless key

          val = partitions.split(",").map! { |x| Integer(x) }
          raise "Pass valid partition numbers" if val.empty?

          acc[key] = val.sort!
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
