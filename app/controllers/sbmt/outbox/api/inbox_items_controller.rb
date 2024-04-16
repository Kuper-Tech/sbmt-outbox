# frozen_string_literal: true

module Sbmt
  module Outbox
    module Api
      class InboxItemsController < BaseController
        def index
          render_list(Sbmt::Outbox.inbox_item_classes.map do |item|
            Sbmt::Outbox::Api::InboxItem.find_or_initialize(item.box_name)
          end)
        end

        def show
          render_one Sbmt::Outbox::Api::InboxItem.find_or_initialize(params.require(:id))
        end

        def update
          record = Sbmt::Outbox::Api::InboxItem.find_or_initialize(params.require(:id))
          record.assign_attributes(
            params.require(:inbox_item).permit(:polling_enabled)
          )
          record.save

          render_one record
        end

        def destroy
          record = Sbmt::Outbox::Api::InboxItem.find(params.require(:id))
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
