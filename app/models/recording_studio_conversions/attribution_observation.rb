# frozen_string_literal: true

module RecordingStudioConversions
  # One captured field. Historical rows stay. There is no column per provider.
  class AttributionObservation < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_attribution_observations"

    validates :visitor_id, :provider, :field_name, :value, :source, :consent_category, :captured_at, presence: true
    validates :value, length: { maximum: 512 }
    validates :source, inclusion: { in: Adapters::SOURCES.map(&:to_s) }
  end
end
