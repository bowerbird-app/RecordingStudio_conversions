# frozen_string_literal: true

module RecordingStudioConversions
  # Host registration of provider adapters and the destinations that enable them.
  module ProviderConfiguration
    def register_adapter(key, adapter_class)
      adapters.register(key, adapter_class, subscriptions: subscriptions)
    end

    def destination(key, adapter:, **options)
      adapter_key = adapter.to_sym
      raise ArgumentError, "unknown adapter #{adapter_key}" unless adapters.registered?(adapter_key)
      raise ArgumentError, "destination #{key} is already registered" if destination_key?(key)

      @destinations << Adapters::Destination.new(key.to_sym, adapter_key, options.freeze)
    end

    def destinations
      @destinations.dup.freeze
    end

    def destination_for(key)
      found = @destinations.find { |item| item.key == key.to_sym }
      return found if found

      raise ArgumentError, "unknown destination #{key}"
    end

    def adapter_for(key)
      adapters.fetch(destination_for(key).adapter_key)
    end

    def enabled_adapters
      destinations.map { |item| adapters.fetch(item.adapter_key) }.uniq
    end

    def clear_destinations!
      @destinations = []
    end

    def clear_adapters!
      @adapters = Adapters::Registry.new
      clear_destinations!
    end

    private

    def destination_key?(key)
      @destinations.any? { |item| item.key == key.to_sym }
    end
  end
end
