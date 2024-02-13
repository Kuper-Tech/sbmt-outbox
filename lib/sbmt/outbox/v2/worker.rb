# frozen_string_literal: true

require "redlock"
require "sbmt/outbox/v2/poller"

module Sbmt
  module Outbox
    module V2
      class Worker
        def initialize(boxes:)
          @poller = Poller.new(boxes: boxes)
        end

        def start
          poller.start

          # TODO: processor.start
          # TODO: non-blocking start
        end
      end
    end
  end
end
