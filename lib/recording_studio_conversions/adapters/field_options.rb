# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Turns a field declaration into a Field. Unknown options raise.
    module FieldOptions
      KNOWN = %i[
        type source required required_for alternatives transform capture
        retention consent sensitivity events channels
      ].freeze

      module_function

      def build(kind, name, consent_category:, **options)
        reject_unknown!(name, options)
        field = Field.new(**attributes(kind, name, consent_category, options))
        reject_self_alternative!(field)
        reject_required_outside_events!(field)
        field
      end

      def reject_unknown!(name, options)
        unknown = options.keys - KNOWN
        return if unknown.empty?

        raise ArgumentError, "field #{name} has unknown options #{unknown.join(', ')}"
      end

      def reject_self_alternative!(field)
        return unless field.alternatives.include?(field.name)

        raise ArgumentError, "field #{field.name} cannot list itself as an alternative"
      end

      def reject_required_outside_events!(field)
        return if field.events.empty?

        extra = field.required_for - field.events
        return if extra.empty?

        raise ArgumentError, "field #{field.name} required_for is outside its events"
      end

      def attributes(kind, name, consent_category, options)
        checked_name!(name)
        { name: name.to_sym, kind: kind_for(kind) }
          .merge(collection(name, options))
          .merge(policy(name, consent_category, options))
      end

      def collection(name, options)
        {
          type: FieldCoercion.one_of(options.fetch(:type, :string), TYPES, "type", name),
          source: FieldCoercion.one_of(FieldCoercion.fetch_option(options, :source, name), SOURCES, "source", name),
          capture: FieldCoercion.one_of(options.fetch(:capture, :request), CAPTURES, "capture", name),
          transform: FieldCoercion.optional_symbol(options[:transform], name),
          alternatives: FieldCoercion.symbols(options.fetch(:alternatives, []), "alternatives", name)
        }
      end

      def policy(name, consent_category, options)
        requirement(name, options).merge(classification(name, consent_category, options))
      end

      def requirement(name, options)
        required = FieldCoercion.fetch_option(options, :required, name)
        {
          required: FieldCoercion.boolean(required, "required", name),
          required_for: FieldCoercion.strings(options.fetch(:required_for, []), name)
        }
      end

      def classification(name, consent_category, options)
        sensitivity = FieldCoercion.fetch_option(options, :sensitivity, name)
        {
          retention: FieldCoercion.duration(options[:retention], name),
          consent_category: FieldCoercion.category(options.fetch(:consent, consent_category), name),
          sensitivity: FieldCoercion.one_of(sensitivity, SENSITIVITIES, "sensitivity", name),
          events: FieldCoercion.strings(options.fetch(:events, []), name),
          channels: FieldCoercion.symbols(options.fetch(:channels, []), "channels", name, CHANNELS)
        }
      end

      def checked_name!(name)
        raise ArgumentError, "field name is required" if name.blank?
      end

      def kind_for(kind)
        FieldCoercion.one_of(kind, KINDS, "kind", "field")
      end
    end
  end
end
