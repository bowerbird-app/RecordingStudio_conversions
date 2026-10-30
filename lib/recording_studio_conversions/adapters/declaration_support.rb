# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Private writers used by Declaration.
    module DeclarationSupport
      include DeclarationInheritance

      def prepare_declarations
        prepare_identity
        prepare_fields
      end

      private

      def prepare_identity
        @key = nil
        @key_from_parent = false
        @consent = nil
        @consent_from_parent = false
        @delivery_channels = nil
        @channels_from_parent = false
      end

      def prepare_fields
        @max_event_age = nil
        @age_from_parent = false
        @browser_module_name = nil
        @browser_module_from_parent = false
        @attribution_fields = []
        @identity_fields = []
        @event_names = {}
      end

      def consent_read?(category, collection, delivery)
        category.nil? && collection == true && delivery == true
      end

      def assign_key(value)
        raise ArgumentError, "adapter key is required" if value.blank?

        symbol = value.to_sym
        raise ArgumentError, "adapter key is already #{@key}" if locked_key?(symbol)

        @key = symbol
        @key_from_parent = false
      end

      def locked_key?(symbol)
        @key && @key != symbol && !@key_from_parent
      end

      def unique_channels(names)
        list = names.map(&:to_sym).uniq
        unknown = list - CHANNELS
        raise ArgumentError, "unknown delivery channel #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "delivery channels cannot be empty" if list.empty?

        list.freeze
      end

      def declare(kind, &block)
        raise ArgumentError, "declare consent before fields" if @consent.nil?
        return unless block

        FieldBuilder.new(self, kind).instance_eval(&block)
      end

      def bucket(kind)
        kind == :identity ? @identity_fields : @attribution_fields
      end

      def ensure_unique!(field)
        return unless fields.any? { |existing| existing.name == field.name }

        raise ArgumentError, "field #{field.name} is already declared"
      end

      def ensure_field_channels!(field)
        return if @delivery_channels.nil? || field.channels.empty?

        extra = field.channels - @delivery_channels
        return if extra.empty?

        raise ArgumentError, "field #{field.name} channel #{extra.join(', ')} is not delivered"
      end
    end
  end
end
