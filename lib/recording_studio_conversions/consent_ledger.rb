# frozen_string_literal: true

module RecordingStudioConversions
  # Consent answers. Collection and later resolution both read the latest row.
  module ConsentLedger
    PROVENANCE_SOURCES = %w[browser host].freeze

    module_function

    def granted?(visitor_id:, category:, at: Time.current)
      row = latest(visitor_id, category, at)
      return false if row.nil?

      row.granted && row.withdrawn_at.nil?
    end

    # A signed-in withdrawal carries user_id. Clearing it before the delete keeps
    # that row, so an earlier anonymous grant does not become the latest consent.
    def detach_user!(user_id)
      ConsentRecord.where(user_id: user_id).where.not(withdrawn_at: nil).update_all(user_id: nil)
      ConsentRecord.where(user_id: user_id).delete_all
    end

    def record!(visitor_id:, category:, granted:, user_id: nil, provenance: {})
      recorded_at = Time.current
      ConsentRecord.create!(
        visitor_id: visitor_id, user_id: user_id, category: category.to_s, granted: granted,
        recorded_at: recorded_at, withdrawn_at: granted ? nil : recorded_at, provenance: sanitize(provenance)
      )
    end

    def latest(visitor_id, category, at)
      return if visitor_id.blank? || category.blank?

      ConsentRecord.where(visitor_id: visitor_id, category: category.to_s)
                   .where(recorded_at: ..at)
                   .order(recorded_at: :desc, created_at: :desc)
                   .first
    end

    def sanitize(provenance)
      source = provenance.to_h.stringify_keys["source"].to_s
      unless PROVENANCE_SOURCES.include?(source)
        raise ArgumentError, "consent provenance source must be browser or host"
      end

      { "source" => source }
    end
  end
end
