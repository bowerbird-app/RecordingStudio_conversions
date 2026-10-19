# frozen_string_literal: true

module RecordingStudioConversions
  class Occurrence < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_occurrences"

    def self.matched_first_for_root?(rule_key:, root_recording_id:)
      where(rule_key: rule_key, root_recording_id: root_recording_id, outcome: "matched",
            first_occurrence: true).exists?
    end
  end
end
