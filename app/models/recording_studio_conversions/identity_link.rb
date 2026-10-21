# frozen_string_literal: true

module RecordingStudioConversions
  # Anonymous device key to a verified user. A second user inserts another row.
  class IdentityLink < ActiveRecord::Base
    self.table_name = "recording_studio_conversions_identity_links"

    METHODS = %w[password oauth otp].freeze

    validates :visitor_id, :user_id, :linked_at, presence: true
    validates :auth_method, inclusion: { in: METHODS }, allow_nil: true
    validates :confirmed, inclusion: { in: [true, false] }
  end
end
