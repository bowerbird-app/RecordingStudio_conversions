# frozen_string_literal: true

module RecordingStudioConversions
  class Envelope
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    PROPERTY_KEYS = %w[amount currency first_payment trial_fee method classification path].freeze
    PRIVATE_KEYS = %w[email access_token].freeze

    attr_reader :name, :source_name, :source_event_id, :occurred_at, :schema_version,
                :root_recording_id, :recording_id, :recordable_type, :recordable_id,
                :actor_type, :actor_id, :subject_type, :subject_id, :properties

    def self.from(subscription, payload)
      new(**fields(subscription, payload.symbolize_keys))
    end

    def self.fields(subscription, data)
      event_fields(subscription, data).merge(reference_fields(data)).merge(properties: properties_for(data))
    end

    def self.event_fields(subscription, data)
      user_id = uuid(data[:user_id])
      {
        name: subscription.canonical_name,
        source_name: subscription.source_name,
        source_event_id: (data[:event_id] || user_id).to_s.presence,
        occurred_at: data[:occurred_at] || Time.current,
        schema_version: data[:schema_version] || 1,
        actor_type: user_id ? "User" : data[:actor_type],
        actor_id: user_id || uuid(data[:actor_id])
      }
    end

    def self.reference_fields(data)
      {
        root_recording_id: uuid(data[:root_recording_id]),
        recording_id: uuid(data[:recording_id]),
        recordable_type: data[:recordable_type] || data[:recording_type],
        recordable_id: uuid(data[:recordable_id]),
        subject_type: data.dig(:subject, :type) || subject_type_for(data),
        subject_id: uuid(data.dig(:subject, :id) || data[:subscription_id] || data[:recording_id])
      }
    end

    def self.uuid(value)
      text = value.to_s
      text if text.match?(UUID)
    end

    def self.subject_type_for(data)
      return "Subscription" if data[:subscription_id]
      return data[:recordable_type] || data[:recording_type] if data[:recording_id]

      nil
    end

    def self.properties_for(data)
      properties = data[:properties].is_a?(Hash) ? data[:properties].stringify_keys : {}
      PROPERTY_KEYS.each { |key| properties[key] = data[key.to_sym] if data.key?(key.to_sym) }
      properties.except(*PRIVATE_KEYS)
    end

    def initialize(**attributes)
      attributes.each { |key, value| instance_variable_set(:"@#{key}", value) }
    end

    def usable?
      source_event_id.present?
    end

    def occurrence_columns
      event_columns.merge(reference_columns)
    end

    def event_columns
      {
        source_event_name: name,
        source_event_id: source_event_id,
        source: source_name,
        schema_version: schema_version,
        occurred_at: occurred_at,
        properties: properties
      }
    end

    def reference_columns
      {
        root_recording_id: root_recording_id,
        recording_id: recording_id,
        recordable_type: recordable_type,
        recordable_id: recordable_id,
        subject_type: subject_type,
        subject_id: subject_id,
        actor_type: actor_type,
        actor_id: actor_id
      }
    end
  end
end
