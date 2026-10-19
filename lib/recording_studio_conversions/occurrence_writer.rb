# frozen_string_literal: true

module RecordingStudioConversions
  class OccurrenceWriter
    Change = Data.define(:rule, :envelope, :subject, :outcome, :reason)
    def initialize(confirmations:)
      @confirmations = confirmations
    end

    def save(change)
      Occurrence.transaction(requires_new: true) do
        existing = Occurrence.lock.find_by(rule_key: change.rule.key, source_event_id: change.envelope.source_event_id)
        next revise(existing, change) if existing

        Occurrence.create!(attributes(change))
      end
    rescue ActiveRecord::RecordNotUnique
      recover(change)
    end

    def revise(existing, change)
      return existing if existing.outcome == "matched"

      existing.update!(attributes(change).except(:rule_key, :source_event_id))
      existing
    end

    private

    def recover(change)
      existing = Occurrence.find_by(rule_key: change.rule.key, source_event_id: change.envelope.source_event_id)
      return revise(existing, change.with(outcome: "suppressed", reason: "already_recorded")) if existing

      Occurrence.transaction(requires_new: true) do
        Occurrence.create!(attributes(change.with(outcome: "suppressed", reason: "already_recorded")))
      end
    end

    def attributes(change)
      change.envelope.occurrence_columns.merge(assignment(change))
    end

    def assignment(change)
      {
        rule_key: change.rule.key,
        attribution_subject_type: change.subject&.subject_type,
        attribution_subject_id: change.subject&.subject_id,
        outcome: change.outcome,
        suppression_reason: change.reason,
        confirmed_at: confirmed_at_for(change.envelope, change.subject),
        first_occurrence: change.rule.first_occurrence && change.outcome == "matched"
      }
    end

    def confirmed_at_for(envelope, subject)
      user_id = user_id_for(envelope, subject)
      return unless user_id

      _status, confirmed_at = @confirmations[user_id] ||= UserConfirmation.lookup(user_id)
      confirmed_at
    end

    def user_id_for(envelope, subject)
      return subject.subject_id if subject&.subject_type == UserConfirmation.user_class_name
      return envelope.actor_id if envelope.actor_type == UserConfirmation.user_class_name

      nil
    end
  end
end
