# frozen_string_literal: true

module Sbmt
  module Outbox
    module Api
      class BaseController < Sbmt::Outbox.action_controller_base_class
        private

        def render_ok
          render json: "OK"
        end

        def render_one(record)
          render json: record
        end

        def render_list(records)
          response.headers["X-Total-Count"] = records.size
          render json: records
        end
      end
    end
  end
end
