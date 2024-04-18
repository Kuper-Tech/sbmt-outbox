# frozen_string_literal: true

module Sbmt
  module Outbox
    module Api
      class OutboxClassesController < BaseController
        def index
          render_list(Sbmt::Outbox.outbox_item_classes.map do |item|
            Api::OutboxClass.find_or_initialize(item.box_name)
          end)
        end

        def show
          render_one Api::OutboxClass.find_or_initialize(params.require(:id))
        end

        def update
          record = Api::OutboxClass.find_or_initialize(params.require(:id))
          record.assign_attributes(
            params.require(:outbox_class).permit(:polling_enabled)
          )
          record.save

          render_one record
        end

        def destroy
          record = Api::OutboxClass.find(params.require(:id))
          unless record
            render_ok
            return
          end

          record.destroy

          render_one record
        end
      end
    end
  end
end
