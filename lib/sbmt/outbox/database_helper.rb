# frozen_string_literal: true

module Sbmt
  module Outbox
    module DatabaseHelper
      extend self

      def clear_active_connections
        if support_connection_handling?
          if legacy_connection_handling?
            ActiveRecord::Base.connection_handlers.each do |_role, handler|
              handler.clear_all_connections!
            end
          else
            ActiveRecord::Base.connection_handler
              .all_connection_pools
              .each(&:clear_reloadable_connections!)
          end
        else
          ::ActiveRecord::Base.clear_active_connections!
        end
      end

      def support_connection_handling?
        ActiveRecord.respond_to?(:legacy_connection_handling) ||
          ActiveRecord::Base.respond_to?(:legacy_connection_handling)
      end

      def legacy_connection_handling?
        if ActiveRecord.respond_to?(:legacy_connection_handling)
          ActiveRecord.legacy_connection_handling
        else
          ActiveRecord::Base.legacy_connection_handling
        end
      end
    end
  end
end
