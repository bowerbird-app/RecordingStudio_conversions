# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Copies a parent adapter's declarations and lets a subclass override each
    # one once. A second declaration in the same class raises.
    module DeclarationInheritance
      def copy_declarations_from(parent)
        copy_identity_from(parent)
        copy_contract_from(parent)
      end

      private

      def copy_identity_from(parent)
        @key = parent.key
        @key_from_parent = !@key.nil?
        copy_parent_contract(parent)
      end

      def copy_parent_contract(parent)
        copy_parent_consent(parent)
        copy_parent_limits(parent)
      end

      def copy_parent_consent(parent)
        @consent = parent.consent
        @consent_from_parent = !@consent.nil?
        channels = parent.declared_delivery_channels
        @delivery_channels = channels&.dup&.freeze
        @channels_from_parent = !@delivery_channels.nil?
      end

      def copy_parent_limits(parent)
        @max_event_age = parent.max_event_age
        @age_from_parent = !@max_event_age.nil?
        @browser_module_name = parent.browser_module
        @browser_module_from_parent = !@browser_module_name.nil?
      end

      def copy_contract_from(parent)
        @attribution_fields = parent.attribution_fields.dup
        @identity_fields = parent.identity_fields.dup
        @event_names = parent.conversion_events.dup
      end

      def assign_consent(category, collection, delivery)
        raise ArgumentError, "consent category is required" if category.blank?
        raise ArgumentError, "consent is already declared" if consent_locked?

        @consent = Consent.build(category: category, collection: collection, delivery: delivery)
        @consent_from_parent = false
        retag_inherited_fields(@consent.category)
      end

      def retag_inherited_fields(category)
        @attribution_fields = retagged(@attribution_fields, category)
        @identity_fields = retagged(@identity_fields, category)
      end

      def retagged(fields, category)
        Array(fields).map { |field| field.with(consent_category: category) }
      end

      def consent_locked?
        @consent && !@consent_from_parent
      end

      def assign_channels(names)
        raise ArgumentError, "delivery channels are already declared" if channels_locked?

        list = unique_channels(names)
        @delivery_channels = list
        @channels_from_parent = false
        fields.each { |field| ensure_field_channels!(field) }
        list
      end

      def channels_locked?
        @delivery_channels && !@channels_from_parent
      end

      def assign_age(duration)
        raise ArgumentError, "max event age is already declared" if age_locked?
        raise ArgumentError, "max event age must be a duration" unless duration.is_a?(ActiveSupport::Duration)

        @max_event_age = duration
        @age_from_parent = false
      end

      def age_locked?
        @max_event_age && !@age_from_parent
      end

      def assign_browser_module(name)
        raise ArgumentError, "browser module is already declared" if browser_module_locked?
        raise ArgumentError, "browser module must be a name" if name.blank?

        @browser_module_name = name.to_s
        @browser_module_from_parent = false
      end

      def browser_module_locked?
        @browser_module_name && !@browser_module_from_parent
      end
    end
  end
end
