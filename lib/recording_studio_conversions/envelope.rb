# frozen_string_literal: true

module RecordingStudioConversions
  module EnvelopeCoercion
    module_function

    def source_event_id(value)
      return if value.is_a?(Array) || value.is_a?(Hash)

      text = value.to_s
      text if text.match?(Envelope::UUID)
    end

    def schema_version_for(subscription, data)
      return data[:schema_version] if data.key?(:schema_version)
      return Configuration::SUPPORTED_SCHEMA_VERSION if subscription.canonical_name == "users.registered"

      nil
    end
  end

  class Envelope
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    attr_reader :name, :source_name, :source_event_id, :occurred_at, :schema_version,
                :root_recording_id, :recording_id, :recordable_type, :recordable_id,
                :actor_type, :actor_id, :subject_type, :subject_id, :visitor_id, :properties

    def self.from_record(occurrence)
      new(**EnvelopeRecord.fields(occurrence))
    end

    def self.from(subscription, payload)
      data = payload.symbolize_keys
      envelope = new(**fields(subscription, data))
      envelope.log_unusable unless envelope.usable?
      envelope
    end

    def self.fields(subscription, data)
      event_fields(subscription, data).merge(reference_fields(data)).merge(
        visitor_id: VisitorId.resolve(data),
        properties: EnvelopeProperties.build(data)
      )
    end

    def self.event_fields(subscription, data)
      user_id = uuid(data[:user_id])
      {
        name: subscription.canonical_name,
        source_name: subscription.source_name,
        source_event_id: EnvelopeCoercion.source_event_id(data[subscription.id_key]),
        occurred_at: data[:occurred_at] || Time.current,
        schema_version: EnvelopeCoercion.schema_version_for(subscription, data),
        actor_type: user_id ? UserConfirmation.user_class_name.presence : data[:actor_type],
        actor_id: user_id || uuid(data[:actor_id])
      }
    end

    def self.reference_fields(data)
      {
        root_recording_id: uuid(data[:root_recording_id]),
        recording_id: uuid(data[:recording_id]),
        recordable_type: data[:recordable_type],
        recordable_id: uuid(data[:recordable_id]),
        subject_type: subject_type_for(data),
        subject_id: uuid(data[:subscription_id] || data[:recording_id])
      }
    end

    def self.uuid(value)
      text = value.to_s
      text if text.match?(UUID)
    end

    def self.subject_type_for(data)
      return "Subscription" if data[:subscription_id]
      return "Recording" if data[:recording_id]

      nil
    end

    def initialize(**attributes)
      attributes.each { |key, value| instance_variable_set(:"@#{key}", value) }
    end

    def usable?
      source_event_id.present? && schema_version == Configuration::SUPPORTED_SCHEMA_VERSION
    end

    def log_unusable
      message = "unusable conversions envelope #{source_name} id=#{source_event_id.inspect} schema=#{schema_version}"
      Rails.logger.warn(message) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      ActiveSupport::Notifications.instrument(
        Configuration::UNUSABLE_EVENT,
        source_name: source_name,
        source_event_id: source_event_id,
        schema_version: schema_version
      )
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
        visitor_id: visitor_id,
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
