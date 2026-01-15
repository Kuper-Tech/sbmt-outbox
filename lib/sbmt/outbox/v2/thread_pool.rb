# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      class ThreadPool
        delegate :logger, to: "Sbmt::Outbox"

        BREAK = Object.new.freeze
        SKIPPED = Object.new.freeze
        PROCESSED = Object.new.freeze

        def initialize(concurrency:, name: "thread_pool", random_startup_delay: true, start_async: true, &block)
          self.concurrency = concurrency
          self.name = name
          self.random_startup_delay = random_startup_delay
          self.start_async = start_async
          self.task_source = block
          self.task_mutex = Mutex.new
          self.stopped = true
          self.threads = Concurrent::Array.new
        end

        def next_task
          task_mutex.synchronize do
            return if stopped
            task = task_source.call

            if task == BREAK
              self.stopped = true
              logger.log_debug("#{name}: received BREAK signal, stopping thread pool")
              return
            end

            task
          end
        end

        def start
          self.stopped = false

          mode = start_async ? "async" : "sync"
          logger.log_info("#{name}: starting #{concurrency} threads in #{mode} mode")

          result = run_threads do |task|
            logger.with_tags(worker: worker_number) do
              yield worker_number, task
            end
          end

          logger.log_info("#{name}: thread pool started with #{concurrency} threads")

          raise result if result.is_a?(Exception)
        end

        def stop
          logger.log_info("#{name}: stopping thread pool")
          self.stopped = true

          threads.map(&:join) if start_async
        ensure
          stop_threads
          logger.log_info("#{name}: thread pool stopped")
        end

        def running?
          if stopped
            logger.log_info("#{name}: checking if running: stopped")
            return false
          end

          true
        end

        def alive?(timeout)
          if stopped
            logger.log_info("#{name}: checking if alive: stopped")
            return false
          end

          deadline = Time.current - timeout
          alive_threads = threads.select do |thread|
            next false unless thread.alive?

            last_active_at = last_active_at(thread)
            if last_active_at
              deadline < last_active_at
            else
              false
            end
          end

          unless alive_threads.length == concurrency
            logger.log_info("#{name}: checking if alive: false, only #{alive_threads.length}/#{concurrency} threads alive")
            return false
          end

          true
        end

        private

        attr_accessor :concurrency, :name, :random_startup_delay, :task_source, :task_mutex, :stopped, :start_async, :threads

        def touch_worker!
          self.last_active_at = Time.current
        end

        def worker_number(thread = Thread.current)
          thread.thread_variable_get("#{name}_worker_number:#{object_id}")
        end

        def last_active_at(thread = Thread.current)
          thread.thread_variable_get("#{name}_last_active_at:#{object_id}")
        end

        def run_threads
          exception = nil

          in_threads do |worker_num|
            logger.log_debug("#{name}: worker #{worker_num} starting")
            self.worker_number = worker_num
            # We don't want to start all threads at the same time
            sleep(rand * (worker_num + 1)) if random_startup_delay

            touch_worker!

            until exception
              task = next_task
              break unless task

              touch_worker!

              begin
                yield task
              rescue Exception => e # rubocop:disable Lint/RescueException
                logger.log_error("#{name}: worker #{worker_num} caught exception in task: #{e.class} - #{e.message}")
                exception = e
              end
            end
          end

          logger.log_info("#{name}: run_threads completed, exception: #{exception&.inspect}")
          exception
        end

        def in_threads
          Thread.handle_interrupt(Exception => :never) do
            Thread.handle_interrupt(Exception => :immediate) do
              logger.log_info("#{name}: creating #{concurrency} threads")
              concurrency.times do |i|
                threads << Thread.new { yield(i) }
              end
              threads.map(&:value) unless start_async
            end
          ensure
            logger.log_debug("#{name}: in_threads ensuring stop_threads")
            stop_threads unless start_async
          end
        end

        def stop_threads
          logger.log_debug("#{name}: stop_threads called, clearing #{threads.length} threads")
          threads.each do |thread|
            logger.log_debug("#{name}: killing thread #{thread.object_id}")
            thread.kill
          end
          threads.clear
          logger.log_debug("#{name}: stop_threads completed")
        end

        def worker_number=(num)
          Thread.current.thread_variable_set("#{name}_worker_number:#{object_id}", num)
        end

        def last_active_at=(at)
          Thread.current.thread_variable_set("#{name}_last_active_at:#{object_id}", at)
        end
      end
    end
  end
end
