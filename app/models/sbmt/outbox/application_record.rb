# frozen_string_literal: true

module Sbmt
  module Outbox
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
