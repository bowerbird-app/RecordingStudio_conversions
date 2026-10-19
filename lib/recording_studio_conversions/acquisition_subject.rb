# frozen_string_literal: true

module RecordingStudioConversions
  class AcquisitionSubject < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_acquisition_subjects"

    def self.record!(root_recording_id:, user_id:)
      row = find_or_initialize_by(root_recording_id: root_recording_id)
      row.subject_type = "User"
      row.subject_id = user_id
      row.recorded_at = Time.current
      row.save!
      row
    end

    def self.for_root(root_recording_id)
      find_by(root_recording_id: root_recording_id)
    end
  end
end
