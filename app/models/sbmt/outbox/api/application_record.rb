# frozen_string_literal: true

module Sbmt
  module Outbox
    module Api
      class ApplicationRecord
        include ActiveModel::Model
        include ActiveModel::Attributes

        delegate :redis, to: "Sbmt::Outbox"

        class << self
          delegate :redis, to: "Sbmt::Outbox"

          def find(id)
            attributes = redis.call "HGETALL", redis_key(id)
            return nil if attributes.empty?

            new(attributes)
          end

          def find_or_initialize(id, params = {})
            record = find(id)
            record || new(params.merge(id: id))
          end

          def delete(id)
            redis.call "DEL", redis_key(id)
          end

          def attributes(*attrs)
            attrs.each do |name|
              attribute name
            end
          end

          def attribute(name, type = ActiveModel::Type::Value.new, **options)
            super
            # Add predicate methods for boolean types
            alias_method :"#{name}?", name if type == :boolean || type.is_a?(ActiveModel::Type::Boolean)
          end

          def redis_key(id)
            "#{name}:#{id}"
          end
        end

        def initialize(params)
          super
          assign_attributes(params)
        end

        def save
          redis.call "HMSET", redis_key, attributes.to_a.flatten.map(&:to_s)
        end

        def destroy
          self.class.delete(id)
        end

        def as_json(*)
          attributes
        end

        def eql?(other)
          return false unless other.is_a?(self.class)
          id == other.id
        end

        alias_method :==, :eql?

        private

        def redis_key
          self.class.redis_key(id)
        end
      end
    end
  end
end
