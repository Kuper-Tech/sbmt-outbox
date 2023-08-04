# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Values
        VALUES_PATH = "configs/values.yaml"

        private

        def add_item_to_values(deployment_name, item_path)
          template_data = <<~RUBY
            #{deployment_name}:
              replicas:
                _default: 1
                prod: 2
              command:
                - /bin/sh
                - -c
                - exec bundle exec outbox start --box #{item_path} --concurrency 4
              readinessProbe:
                httpGet:
                  path: /readiness/outbox
                  port: SET-UP-YOUR-HEALTHCHECK-PORT-HERE
              livenessProbe:
                httpGet:
                  path: /liveness/outbox
                  port: SET-UP-YOUR-HEALTHCHECK-PORT-HERE
              resources:
                prod:
                  requests:
                    cpu: "500m"
                    memory: "512Mi"
                  limits:
                    cpu: "1"
                    memory: "1Gi"

          RUBY

          inject_into_file VALUES_PATH, optimize_indentation(template_data, 2), after: /^deployments:\s*\n/
        end

        def dasherize_item(item_path)
          item_path.tr("/", "-").dasherize
        end
      end
    end
  end
end
