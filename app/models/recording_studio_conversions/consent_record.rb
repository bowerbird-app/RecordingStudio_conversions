# frozen_string_literal: true

module RecordingStudioConversions
  # A visitor's answer for one consent category. Delivery reads the latest row.
  class ConsentRecord < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_consents"

    validates :visitor_id, :category, :recorded_at, presence: true
    validates :granted, inclusion: { in: [true, false] }
  end
end
