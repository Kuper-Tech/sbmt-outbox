# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Alerts
        ALERTS_PATH = "configs/alerts.yaml"

        private

        def patch_alerts_with_template_data
          alert_declarations_data = <<~YAML
            outbox-worker-missing-activity: &outbox-worker-missing-activity
              name: OutboxWorkerMissingActivity
              summary: "Outbox daemon doesn't process some jobs"
              description: "Отсутствие активности Outbox daemon для `{{ $labels.name }}:`{{ $labels.partition }}`"
              expr: sum by (name, partition) (rate(box_worker_job_counter{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE', state='processed'}[5m])) == 0
              for: 5m
              runbook: https://wiki.sbmt.io/pages/viewpage.action?pageId=3053201983
              dashboard: https://grafana.sbmt.io/d/vMyPDav4z/service-ruby-outbox-inbox-worker
              severity: error
              slack: SET-UP-YOUR-SLACK-CHANNEL-NAME-HERE
            
            outbox-worker-errors: &outbox-worker-errors
              name: OutboxWorkerErrors
              summary: "Ошибка обработки батча в демоне outbox"
              description: "Количество ошибок в Outbox daemon при загрузке батча по `{{ $labels.name }}` превышает 10%"
              expr: (sum(increase(box_worker_job_counter{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE', state='failed'}[5m])) by (name) / sum(increase(box_worker_job_counter{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE'}[5m])) by (name)) > 0.1
              for: 5m
              runbook: https://wiki.sbmt.io/pages/viewpage.action?pageId=3053201983
              dashboard: https://grafana.sbmt.io/d/vMyPDav4z/service-ruby-outbox-inbox-worker
              severity: error
              slack: SET-UP-YOUR-SLACK-CHANNEL-NAME-HERE
  
            outbox-items-errors: &outbox-items-errors
              name: OutboxItemsErrors
              summary: "Ошибки обработки outbox/inbox items"
              description: "Количество ошибок при обработке таблиц outbox/inbox по `{{ $labels.name }}` превышает 5%"
              expr: >-
                (sum(increase(outbox_error_counter{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE'}[5m])) by (name) / sum(increase(outbox_sent_counter{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE'}[5m])) by (name)) > 0.05
              for: 1m
              runbook: https://wiki.sbmt.io/pages/viewpage.action?pageId=3051202830
              dashboard: https://grafana.sbmt.io/d/vMyPDav4z/service-ruby-outbox-inbox-worker
              severity: degradation
              slack: SET-UP-YOUR-SLACK-CHANNEL-NAME-HERE
            
            outbox-items-lag: &outbox-items-lag
              name: OutboxQueueLag
              summary: "Лаг при обработке outbox/inbox items"
              description: "Текущий лаг очереди обработки таблиц outbox/inbox по `{{ $labels.name }}:{{ $labels.partition }}` превышает `{{ $value }}` секунд"
              expr: >-
                (sum(rate(outbox_process_latency_seconds_sum{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE'}[5m])) by (name, partition) / sum(rate(outbox_process_latency_seconds_count{service_name='SET-UP-YOUR-SERVICE-NAME-YABEDA-TAG-HERE'}[5m])) by (name, partition)) > 300
              for: 5m
              runbook: https://wiki.sbmt.io/pages/viewpage.action?pageId=3042429449
              dashboard: https://grafana.sbmt.io/d/vMyPDav4z/service-ruby-outbox-inbox-worker
              severity: degradation
              slack: SET-UP-YOUR-SLACK-CHANNEL-NAME-HERE

          YAML

          alert_aliases_data = <<~YAML
            outbox:
              - <<: *outbox-worker-missing-activity
              - <<: *outbox-worker-errors
              - <<: *outbox-items-errors
              - <<: *outbox-items-lag
          YAML

          alert_initial_data = <<~YAML
            #{alert_declarations_data}

            prometheusRules:
              prod:
            #{optimize_indentation(alert_aliases_data, 4)}
          YAML

          if File.binread(ALERTS_PATH).match?(/^prometheusRules:\s*\n/)
            inject_into_file ALERTS_PATH, optimize_indentation(alert_declarations_data, 0), before: /^prometheusRules:\s*\n/
            inject_into_file ALERTS_PATH, optimize_indentation(alert_aliases_data, 4), after: /^prometheusRules:\s*\n.+?^\s*prod:\s*\n/m
          else
            # alerts are not configured
            append_to_file ALERTS_PATH, optimize_indentation(alert_initial_data, 0)
          end
        end
      end
    end
  end
end
