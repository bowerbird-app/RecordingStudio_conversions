# frozen_string_literal: true

module RecordingStudioConversions
  class Processor
    def self.call(subscription, payload)
      new(subscription, payload).call
    end

    def initialize(subscription, payload)
      @subscription = subscription
      @payload = payload
    end

    def call
      return [] unless @payload.is_a?(Hash)

      envelope = Envelope.from(@subscription, @payload)
      return [] unless envelope.usable?

      RecordingStudioConversions.configuration.rules.filter_map do |rule|
        record(rule, envelope) if rule.matches?(envelope)
      end
    end

    private

    def record(rule, envelope)
      subject = AcquisitionSubject.for_root(envelope.root_recording_id) if envelope.root_recording_id
      outcome, reason = decision(rule, envelope, subject)
      insert(rule, envelope, subject, outcome, reason)
    end

    def decision(rule, envelope, subject)
      unresolved(envelope, subject) ||
        unconfirmed(envelope, subject) ||
        duplicate(rule, subject) ||
        %w[matched].push(nil)
    end

    def unresolved(envelope, subject)
      return unless envelope.root_recording_id && subject.nil?

      %w[suppressed unresolved_acquisition_subject]
    end

    def unconfirmed(envelope, subject)
      user_id = user_id_for(envelope, subject)
      return unless user_id

      status, confirmed_at = UserConfirmation.lookup(user_id)
      return %w[suppressed unknown_user] if status == :missing
      return %w[suppressed unconfirmed_user] if confirmed_at.nil?

      nil
    end

    def duplicate(rule, subject)
      return unless rule.first_occurrence && subject
      return unless Occurrence.matched_first?(rule_key: rule.key, attribution_subject_id: subject.subject_id)

      %w[suppressed already_recorded]
    end

    def user_id_for(envelope, subject)
      return subject.subject_id if subject&.subject_type == "User"
      return envelope.actor_id if envelope.actor_type == "User"

      nil
    end

    def insert(rule, envelope, subject, outcome, reason)
      Occurrence.create!(attributes(rule, envelope, subject, outcome, reason))
    rescue ActiveRecord::RecordNotUnique
      existing = Occurrence.find_by(rule_key: rule.key, source_event_id: envelope.source_event_id)
      return existing if existing

      Occurrence.create!(
        attributes(rule, envelope, subject, "suppressed", "already_recorded").merge(first_occurrence: false)
      )
    end

    def attributes(rule, envelope, subject, outcome, reason)
      envelope.occurrence_columns.merge(
        rule_key: rule.key,
        attribution_subject_type: subject&.subject_type,
        attribution_subject_id: subject&.subject_id,
        visitor_id: VisitorId.current,
        outcome: outcome,
        suppression_reason: reason,
        confirmed_at: confirmed_at_for(envelope, subject),
        first_occurrence: rule.first_occurrence && outcome == "matched"
      )
    end

    def confirmed_at_for(envelope, subject)
      user_id = user_id_for(envelope, subject)
      return unless user_id

      _status, confirmed_at = UserConfirmation.lookup(user_id)
      confirmed_at
    end
  end
end
