# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Outboxfile
        OUTBOXFILE_PATH = "Outboxfile"

        private

        def create_outboxfile_with_template(template_name)
          template template_name, OUTBOXFILE_PATH
        end
      end
    end
  end
end
