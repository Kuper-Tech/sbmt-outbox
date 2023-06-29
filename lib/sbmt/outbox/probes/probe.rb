# frozen_string_literal: true

module Sbmt
  module Outbox
    module Probes
      class Probe
        DEFAULT_PROBE_PORT = 5555
        class << self
          def run_probes
            ::HttpHealthCheck.run_server_async(
              port: probe_port,
              rack_app: HttpHealthCheck::RackApp.configure do |c|
                c.logger Rails.logger
                c.probe "/readiness/outbox" do |_env|
                  code = Sbmt::Outbox.current_worker.ready? ? 200 : 500
                  [code, {}, ["Outbox version: #{Sbmt::Outbox::VERSION}"]]
                end

                c.probe "/liveness/outbox" do |_env|
                  code = Sbmt::Outbox.current_worker.alive? ? 200 : 500
                  [code, {}, ["Outbox version: #{Sbmt::Outbox::VERSION}"]]
                end
              end
            )
          end

          private

          def probe_port
            return DEFAULT_PROBE_PORT if Outbox.yaml_config["probes"].nil?

            Sbmt::Outbox.yaml_config.fetch(:probes).fetch(:port)
          end
        end
      end
    end
  end
end
