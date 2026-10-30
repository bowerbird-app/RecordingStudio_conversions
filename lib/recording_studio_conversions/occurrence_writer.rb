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
    rescue ActiveRecord::RecordNotUnique => e
      recover(change, e)
    end

    def revise(existing, change)
      return existing if existing.outcome == "matched"

      existing.update!(attributes(change).except(:rule_key, :source_event_id))
      existing
    end

    def recover(change, error = nil)
      existing = Occurrence.find_by(rule_key: change.rule.key, source_event_id: change.envelope.source_event_id)
      return mark_already_recorded(existing) if existing && first_occurrence_conflict?(error)
      return existing if existing

      Occurrence.transaction(requires_new: true) do
        Occurrence.create!(attributes(change.with(outcome: "suppressed", reason: "already_recorded")))
      end
    end

    private

    def first_occurrence_conflict?(error)
      error&.message.to_s.include?("idx_rs_conversions_first_occurrence_root")
    end

    def mark_already_recorded(existing)
      return existing if existing.outcome == "matched"

      existing.update!(outcome: "suppressed", suppression_reason: "already_recorded", first_occurrence: false)
      existing
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
      UserConfirmation.confirming_user_id(envelope, subject)
    end
  end
end
