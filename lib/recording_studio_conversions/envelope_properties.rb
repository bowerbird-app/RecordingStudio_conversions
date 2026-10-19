# frozen_string_literal: true

module RecordingStudioConversions
  module EnvelopeRecord
    module_function

    def fields(occurrence)
      identity(occurrence).merge(references(occurrence))
    end

    def identity(occurrence)
      {
        name: occurrence.source_event_name,
        source_name: occurrence.source,
        source_event_id: occurrence.source_event_id,
        occurred_at: occurrence.occurred_at,
        schema_version: occurrence.schema_version,
        properties: occurrence.properties,
        visitor_id: occurrence.visitor_id
      }
    end

    def references(occurrence)
      {
        root_recording_id: occurrence.root_recording_id,
        recording_id: occurrence.recording_id,
        recordable_type: occurrence.recordable_type,
        recordable_id: occurrence.recordable_id,
        actor_type: occurrence.actor_type,
        actor_id: occurrence.actor_id,
        subject_type: occurrence.subject_type,
        subject_id: occurrence.subject_id
      }
    end
  end

  module EnvelopeProperties
    KEYS = %w[
      amount billing_reason currency first_payment invoice_id method path referrer query_params
      subscription_status
    ].freeze

    module_function

    def build(data)
      properties = copied(data)
      properties["query_params"] = query_params(properties["query_params"]) if properties.key?("query_params")
      drop_blank_strings(properties.compact)
    end

    # Blank strings, including Stripe billing_reason "", are unknown.
    # false is kept: first_payment false is a real value, and compact_blank would drop it.
    def drop_blank_strings(properties)
      properties.reject { |_key, value| value.is_a?(String) && value.blank? }
    end

    def copied(data)
      nested = data[:properties].is_a?(Hash) ? data[:properties].stringify_keys : {}
      KEYS.each_with_object({}) do |key, properties|
        properties[key] = data[key.to_sym] if data.key?(key.to_sym)
        properties[key] = nested[key] if nested.key?(key) && !properties.key?(key)
      end
    end

    def query_params(value)
      return unless value.is_a?(Hash)

      value.stringify_keys
    end
  end
end
