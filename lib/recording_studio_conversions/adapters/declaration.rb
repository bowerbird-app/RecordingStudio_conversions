# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    class FieldBuilder
      def initialize(adapter, kind)
        @adapter = adapter
        @kind = kind
      end

      def field(name, **)
        @adapter.add_field(@kind, name, **)
      end
    end

    # Class methods that record a provider's contract. Extended onto Base.
    module Declaration
      include DeclarationSupport

      def key(value = :unset)
        return @key if value == :unset

        assign_key(value)
      end

      def consent(category: nil, collection: true, delivery: true)
        return @consent if consent_read?(category, collection, delivery)

        assign_consent(category, collection, delivery)
      end

      def delivery_channels(*names)
        return Array(@delivery_channels) if names.empty?

        assign_channels(names)
      end

      def max_event_age(duration = :unset)
        return @max_event_age if duration == :unset

        assign_age(duration)
      end

      def browser_module(name = :unset)
        return @browser_module_name if name == :unset

        assign_browser_module(name)
      end

      # Maps a conversion rule key to the provider event name. The first
      # argument is Rule#key, not the source event name, so purchase and
      # first_purchase can share a source and still differ here.
      def conversion_event(rule_key, as:)
        name = rule_key.to_s
        raise ArgumentError, "conversion event name is required" if name.blank? || as.blank?
        raise ArgumentError, "conversion event #{name} is already declared" if @event_names.key?(name)

        @event_names[name] = as.to_s
      end

      def attribution(&)
        declare(:attribution, &)
      end

      def identity(&)
        declare(:identity, &)
      end

      def add_field(kind, name, **)
        raise ArgumentError, "declare consent before fields" if @consent.nil?

        field = FieldOptions.build(kind, name, consent_category: @consent.category, **)
        ensure_field_channels!(field)
        ensure_unique!(field)
        bucket(kind) << field
        field
      end
    end
  end
end
