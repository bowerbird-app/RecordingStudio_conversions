# frozen_string_literal: true

module RecordingStudioConversions
  class Processor
    def self.call(subscription, payload)
      new(subscription, payload).call
    rescue StandardError => e
      report(e, subscription)
      raise if RecordingStudioConversions.configuration.raise_errors

      []
    end

    def self.reevaluate!(rule_key: nil)
      scope = Occurrence.where(outcome: "suppressed")
      scope = scope.where(rule_key: rule_key.to_s) if rule_key
      scope.filter_map { |occurrence| reevaluate_occurrence(occurrence) }
    end

    def self.reevaluate_occurrence(occurrence)
      rule = RecordingStudioConversions.configuration.rules.find { |item| item.key == occurrence.rule_key }
      return unless rule

      new(nil, {}).revise_stored(rule, occurrence)
    end

    def self.report(exception, subscription)
      ActiveSupport::Notifications.instrument(
        Configuration::FAILED_EVENT,
        error: exception,
        source_name: subscription&.source_name
      )
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.error("[RecordingStudioConversions] #{exception.class}: #{exception.message}")
    end

    def initialize(subscription, payload)
      @subscription = subscription
      @payload = payload
      @confirmations = {}
    end

    def call
      return [] unless @payload.is_a?(Hash)

      envelope = Envelope.from(@subscription, @payload)
      return [] unless envelope.usable?

      RecordingStudioConversions.configuration.rules.filter_map do |rule|
        record(rule, envelope) if rule.matches?(envelope)
      end
    end

    def revise_stored(rule, occurrence)
      envelope = Envelope.from_record(occurrence)
      subject = subject_for(envelope)
      outcome, reason = decision(rule, envelope, subject)
      writer.revise(occurrence, OccurrenceWriter::Change.new(rule, envelope, subject, outcome, reason))
    end

    private

    def record(rule, envelope)
      subject = subject_for(envelope)
      outcome, reason = decision(rule, envelope, subject)
      writer.save(OccurrenceWriter::Change.new(rule, envelope, subject, outcome, reason))
    end

    def subject_for(envelope)
      return unless envelope.root_recording_id

      AcquisitionSubject.for_root(envelope.root_recording_id)
    end

    def decision(rule, envelope, subject)
      unresolved(envelope, subject) ||
        unconfirmed(envelope, subject) ||
        duplicate(rule, envelope, subject) ||
        ["matched", nil]
    end

    def unresolved(envelope, subject)
      return if envelope.name == "views.recorded"
      return unless envelope.root_recording_id && subject.nil?

      %w[suppressed unresolved_acquisition_subject]
    end

    def unconfirmed(envelope, subject)
      user_id = user_id_for(envelope, subject)
      return unless user_id

      status, confirmed_at = confirmation_for(user_id)
      return %w[suppressed unknown_user] if status == :missing
      return %w[suppressed unconfirmed_user] if confirmed_at.nil?

      nil
    end

    def duplicate(rule, envelope, subject)
      return unless rule.first_occurrence
      return %w[suppressed already_recorded] if rooted_duplicate?(rule, envelope)
      return %w[suppressed already_recorded] if subject_duplicate?(rule, envelope, subject)

      nil
    end

    def rooted_duplicate?(rule, envelope)
      return false if envelope.root_recording_id.blank?

      Occurrence.matched_first_for_root?(rule_key: rule.key, root_recording_id: envelope.root_recording_id)
    end

    def subject_duplicate?(rule, envelope, subject)
      return false if envelope.root_recording_id.present? || subject.nil?

      Occurrence.matched_first?(rule_key: rule.key, attribution_subject_id: subject.subject_id)
    end

    def confirmation_for(user_id)
      @confirmations[user_id] ||= UserConfirmation.lookup(user_id)
    end

    def user_id_for(envelope, subject)
      return subject.subject_id if subject&.subject_type == UserConfirmation.user_class_name
      return envelope.actor_id if envelope.actor_type == UserConfirmation.user_class_name

      nil
    end

    def writer
      OccurrenceWriter.new(confirmations: @confirmations)
    end
  end
end
