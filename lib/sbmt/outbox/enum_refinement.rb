# frozen_string_literal: true

module Sbmt
  module Outbox
    module EnumRefinement
      refine ActiveRecord::Base.singleton_class do
        def enum(name, values = nil)
          if Rails::VERSION::MAJOR >= 7
            super
          else
            super(name => values)
          end
        end
      end
    end
  end
end
