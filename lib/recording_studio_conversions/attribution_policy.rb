# frozen_string_literal: true

module RecordingStudioConversions
  # The host resolver must agree with the one acquisition row for the root.
  # A disagreement is ambiguous. Another workspace member is not substituted.
  module AttributionPolicy
    AMBIGUOUS = :ambiguous
    DIAGNOSTIC = "attribution_subject.recording_studio_conversions"
    DEFAULT = lambda do |event|
      AcquisitionSubject.for_root(event.root_recording_id)
    end

    module_function

    def resolve(envelope)
      interpret(envelope, resolver.call(envelope))
    end

    def diagnose(envelope, status)
      ActiveSupport::Notifications.instrument(
        DIAGNOSTIC,
        status: status,
        root_recording_id: envelope.root_recording_id,
        source_event_id: envelope.source_event_id
      )
    end

    def resolver
      RecordingStudioConversions.configuration.attribution_subject_resolver || DEFAULT
    end

    def interpret(envelope, raw)
      return nil if raw.nil?
      return AMBIGUOUS if raw == AMBIGUOUS || raw.is_a?(Array)
      return from_record(envelope, raw) if raw.is_a?(AcquisitionSubject)
      return from_reference(envelope, raw) if reference?(raw)

      AMBIGUOUS
    end

    def from_record(envelope, raw)
      return AMBIGUOUS unless raw.root_recording_id == envelope.root_recording_id

      agree(envelope, raw.subject_type, raw.subject_id)
    end

    def from_reference(envelope, raw)
      agree(envelope, reference_type(raw), reference_id(raw))
    end

    def agree(envelope, type, id)
      stored = AcquisitionSubject.for_root(envelope.root_recording_id)
      return nil if stored.nil?
      return stored if type.to_s == stored.subject_type && id.to_s == stored.subject_id.to_s

      AMBIGUOUS
    end

    def reference?(raw)
      raw.is_a?(Hash) || uuid?(raw)
    end

    def uuid?(raw)
      raw.is_a?(String) && raw.match?(Envelope::UUID)
    end

    def reference_type(raw)
      return UserConfirmation.user_class_name if uuid?(raw)

      raw[:subject_type] || raw["subject_type"]
    end

    def reference_id(raw)
      return raw if uuid?(raw)

      raw[:subject_id] || raw["subject_id"]
    end
  end
end
