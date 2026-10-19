# frozen_string_literal: true

module RecordingStudioConversions
  class Occurrence < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_occurrences"

    def self.matched_first?(rule_key:, attribution_subject_id:)
      where(
        rule_key: rule_key,
        attribution_subject_id: attribution_subject_id,
        outcome: "matched",
        first_occurrence: true
      ).exists?
    end
  end
end
