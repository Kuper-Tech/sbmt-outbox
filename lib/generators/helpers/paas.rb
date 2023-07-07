# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Paas
        APP_MANIFEST_PATH = "configs/app.toml"

        private

        def paas_app?
          File.exist?(APP_MANIFEST_PATH)
        end
      end
    end
  end
end
