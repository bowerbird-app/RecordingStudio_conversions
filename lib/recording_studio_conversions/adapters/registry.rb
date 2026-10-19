# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    class Registry
      def initialize
        @adapters = {}
      end

      def register(key, adapter_class, subscriptions: [], rules: [])
        symbol = key.to_sym
        return @adapters[symbol] if @adapters[symbol].equal?(adapter_class)

        assert_new!(symbol, adapter_class, subscriptions, rules)
        @adapters[symbol] = adapter_class
      end

      def check!(subscriptions:, rules:)
        @adapters.each do |symbol, adapter_class|
          assert_sources!(symbol, adapter_class, subscriptions, rules)
          assert_conversion_events!(symbol, adapter_class, rules)
        end
      end

      def fetch(key)
        @adapters.fetch(key.to_sym) { raise ArgumentError, "unknown adapter #{key}" }
      end

      def registered?(key)
        @adapters.key?(key.to_sym)
      end

      def keys
        @adapters.keys
      end

      private

      def assert_new!(symbol, adapter_class, subscriptions, rules)
        raise ArgumentError, "adapter #{symbol} is already registered" if @adapters.key?(symbol)
        raise ArgumentError, "adapter #{symbol} must inherit from Base" unless adapter?(adapter_class)

        Stability.assert!(adapter_class, symbol)
        assert_key!(symbol, adapter_class)
        assert_complete!(symbol, adapter_class)
        assert_alternatives!(symbol, adapter_class)
        assert_sources!(symbol, adapter_class, subscriptions, rules)
        assert_conversion_events!(symbol, adapter_class, rules)
      end

      def adapter?(adapter_class)
        adapter_class.is_a?(Class) && adapter_class < Base
      end

      def assert_key!(symbol, adapter_class)
        declared = adapter_class.key
        return if declared.nil? || declared == symbol

        raise ArgumentError, "adapter key #{symbol} does not match #{declared}"
      end

      def assert_complete!(symbol, adapter_class)
        raise ArgumentError, "adapter #{symbol} needs a consent category" if adapter_class.consent.nil?
        return if adapter_class.delivery_channels.any?

        raise ArgumentError, "adapter #{symbol} needs a delivery channel"
      end

      def assert_alternatives!(symbol, adapter_class)
        known = adapter_class.fields.map(&:name)
        adapter_class.fields.each { |field| assert_field_alternatives!(symbol, field, known) }
      end

      def assert_field_alternatives!(symbol, field, known)
        missing = field.alternatives - known
        return if missing.empty?

        raise ArgumentError, "adapter #{symbol} field #{field.name} alternative #{missing.join(', ')} is not declared"
      end

      def assert_sources!(symbol, adapter_class, subscriptions, rules)
        known = source_names(subscriptions, rules)
        return if known.empty?

        adapter_class.fields.each { |field| assert_field_events!(symbol, field, known) }
      end

      def source_names(subscriptions, rules)
        names = Array(subscriptions).map { |item| item.canonical_name.to_s }
        names.concat(Array(rules).map { |rule| rule.source.to_s })
        names.uniq
      end

      def assert_field_events!(symbol, field, known)
        unknown = (field.events + field.required_for).uniq - known
        return if unknown.empty?

        list = unknown.join(", ")
        raise ArgumentError, "adapter #{symbol} field #{field.name} event #{list} is not a configured source"
      end

      def assert_conversion_events!(symbol, adapter_class, rules)
        return if Array(rules).empty?

        known = rules.map { |rule| rule.key.to_s }
        unknown = adapter_class.conversion_events.keys - known
        return if unknown.empty?

        raise ArgumentError, "adapter #{symbol} conversion event #{unknown.join(', ')} is not a configured rule"
      end
    end
  end
end
