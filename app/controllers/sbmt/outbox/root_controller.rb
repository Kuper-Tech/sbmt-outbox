# frozen_string_literal: true

module Sbmt
  module Outbox
    class RootController < ActionController::Base
      def index
        @local_endpoint = Outbox.config.ui.local_endpoint
        @cdn_url = Outbox.config.ui.cdn_url
      end
    end
  end
end
