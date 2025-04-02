# frozen_string_literal: true

require "rackup/handler/webrick" if Gem::Version.new(::Rack.release) >= Gem::Version.new("3")

module Sbmt
  module Outbox
    module Probes
      class Metrics
        DEFAULT_YABEDA_PORT = 9090
        DEFAULT_YABEDA_PATH = "/metrics"
        class << self
          def run_metrics
            return unless autostart_yabeda_server?

            if defined?(Yabeda)
              $stdout.puts "Starting metrics http-server..."

              start_webrick(
                Yabeda::Prometheus::Mmap::Exporter::NOT_FOUND_HANDLER,
                middlewares: {::Yabeda::Prometheus::Exporter => {path: DEFAULT_YABEDA_PATH}},
                port: yabeda_port
              )
            end
          end

          private

          def yabeda_port
            Sbmt::Outbox.yaml_config.dig(:metrics, :port) || DEFAULT_YABEDA_PORT
          end

          def start_webrick(app, middlewares:, port:)
            Thread.new do
              webrick.run(
                ::Rack::Builder.new do
                  middlewares.each do |middleware, options|
                    use middleware, **options
                  end
                  run app
                end,
                Host: "0.0.0.0",
                Port: port
              )
            end
          end

          def webrick
            return ::Rack::Handler::WEBrick if Gem::Version.new(::Rack.release) < Gem::Version.new("3")

            ::Rackup::Handler::WEBrick
          end

          def autostart_yabeda_server?
            Sbmt::Outbox.yaml_config.dig(:metrics, :enabled) || false
          end
        end
      end
    end
  end
end
