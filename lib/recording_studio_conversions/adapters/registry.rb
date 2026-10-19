# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    class Registry
      def initialize
        @adapters = {}
      end

      def register(key, adapter_class)
        symbol = key.to_sym
        assert_new!(symbol, adapter_class)
        @adapters[symbol] = adapter_class
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

      def assert_new!(symbol, adapter_class)
        raise ArgumentError, "adapter #{symbol} is already registered" if @adapters.key?(symbol)
        raise ArgumentError, "adapter #{symbol} must inherit from Base" unless adapter?(adapter_class)

        assert_key!(symbol, adapter_class)
        assert_complete!(symbol, adapter_class)
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
    end
  end
end
