# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Shared checks for field option values.
    module FieldCoercion
      module_function

      def fetch_option(options, key, name)
        options.fetch(key)
      rescue KeyError
        raise ArgumentError, "field #{name} needs #{key}"
      end

      def one_of(value, allowed, label, name)
        symbol = value.to_sym
        return symbol if allowed.include?(symbol)

        raise ArgumentError, "field #{name} #{label} #{symbol} is not allowed"
      end

      def symbols(value, label, name, allowed = nil)
        list = Array(value).map(&:to_sym).uniq
        bad = allowed ? list - allowed : []
        raise ArgumentError, "field #{name} #{label} #{bad.join(', ')} is not allowed" if bad.any?

        list.freeze
      end

      def strings(value, name)
        list = Array(value).map(&:to_s)
        raise ArgumentError, "field #{name} list cannot be blank" if list.any?(&:blank?)

        list.freeze
      end

      def boolean(value, label, name)
        return value if [true, false].include?(value)

        raise ArgumentError, "field #{name} #{label} must be true or false"
      end

      def optional_symbol(value, name)
        return if value.nil?
        raise ArgumentError, "field #{name} transform must be a name" if value.blank?

        value.to_sym
      end

      def duration(value, name)
        return if value.nil?
        return value if value.is_a?(ActiveSupport::Duration)

        raise ArgumentError, "field #{name} retention must be a duration"
      end

      def category(value, name)
        raise ArgumentError, "field #{name} needs a consent category" if value.blank?

        value.to_sym
      end
    end
  end
end
