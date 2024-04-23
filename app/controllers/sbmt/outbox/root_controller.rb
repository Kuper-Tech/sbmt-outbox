# frozen_string_literal: true

module Sbmt
  module Outbox
    class RootController < Sbmt::Outbox.action_controller_base_class
      def index
        @local_endpoint = Outbox.config.ui.local_endpoint
        @cdn_url = Outbox.config.ui.cdn_url
      end
    end
  end
end
