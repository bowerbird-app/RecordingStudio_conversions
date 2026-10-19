# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Private writers used by Declaration.
    module DeclarationSupport
      private

      def prepare_declarations
        @key = nil
        @attribution_fields = []
        @identity_fields = []
        @consent = nil
        @delivery_channels = nil
        @max_event_age = nil
        @browser_module_name = nil
        @event_names = {}
      end

      def consent_read?(category, collection, delivery)
        category.nil? && collection == true && delivery == true
      end

      def assign_key(value)
        raise ArgumentError, "adapter key is required" if value.blank?
        raise ArgumentError, "adapter key is already #{@key}" if @key && @key != value.to_sym

        @key = value.to_sym
      end

      def assign_channels(names)
        raise ArgumentError, "delivery channels are already declared" if @delivery_channels

        list = unique_channels(names)
        @delivery_channels = list
        fields.each { |field| ensure_field_channels!(field) }
        list
      end

      def unique_channels(names)
        list = names.map(&:to_sym).uniq
        unknown = list - CHANNELS
        raise ArgumentError, "unknown delivery channel #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "delivery channels cannot be empty" if list.empty?

        list.freeze
      end

      def assign_age(duration)
        raise ArgumentError, "max event age is already declared" if @max_event_age
        raise ArgumentError, "max event age must be a duration" unless duration.is_a?(ActiveSupport::Duration)

        @max_event_age = duration
      end

      def assign_browser_module(name)
        raise ArgumentError, "browser module is already declared" if @browser_module_name
        raise ArgumentError, "browser module must be a name" if name.blank?

        @browser_module_name = name.to_s
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
