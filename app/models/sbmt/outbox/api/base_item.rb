# frozen_string_literal: true

module Sbmt
  module Outbox
    module Api
      class BaseItem < Api::ApplicationRecord
        attribute :id, :string
        attribute :polling_enabled, :boolean, default: -> { !Outbox.yaml_config.fetch(:polling_auto_disabled, false) }
      end
    end
  end
end
