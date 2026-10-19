# frozen_string_literal: true

module RecordingStudioConversions
  class AcquisitionSubject < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_acquisition_subjects"

    def self.record!(root_recording_id:, user_id:)
      upsert(row_for(root_recording_id, user_id), **upsert_options)
      for_root(root_recording_id)
    end

    def self.row_for(root_recording_id, user_id)
      now = Time.current
      {
        id: SecureRandom.uuid, root_recording_id: root_recording_id,
        subject_type: UserConfirmation.user_class_name, subject_id: user_id,
        recorded_at: now, created_at: now, updated_at: now
      }
    end

    def self.upsert_options
      {
        unique_by: :idx_rs_conversions_one_acquisition_user_per_root,
        update_only: %i[subject_type subject_id recorded_at]
      }
    end

    def self.for_root(root_recording_id)
      find_by(root_recording_id: root_recording_id)
    end
  end
end
