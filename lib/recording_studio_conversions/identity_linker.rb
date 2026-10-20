# frozen_string_literal: true

module RecordingStudioConversions
  # Links Root Switchable's device key to users.id. The first pair is kept.
  module IdentityLinker
    module_function

    def from_envelope(envelope)
      return unless envelope.name == "users.registered"
      return if envelope.visitor_id.blank? || envelope.actor_id.blank?

      status, confirmed_at = UserConfirmation.lookup(envelope.actor_id)
      return unless status == :found && confirmed_at

      record!(
        visitor_id: envelope.visitor_id,
        user_id: envelope.actor_id,
        auth_method: envelope.properties["method"],
        confirmed: true
      )
    end

    def from_request(visitor_id:, user:)
      return if visitor_id.blank? || user.nil?
      return unless user.respond_to?(:confirmed?) && user.confirmed?

      record!(visitor_id: visitor_id, user_id: user.id, auth_method: nil, confirmed: true)
    end

    def record!(visitor_id:, user_id:, auth_method:, confirmed:)
      IdentityLink.insert(link_row(visitor_id, user_id, auth_method, confirmed), unique_by: :idx_rs_conv_links_pair)
    end

    def link_row(visitor_id, user_id, auth_method, confirmed)
      now = Time.current
      {
        id: SecureRandom.uuid, visitor_id: visitor_id, user_id: user_id,
        auth_method: allowed_method(auth_method), linked_at: now, confirmed: confirmed,
        created_at: now, updated_at: now
      }
    end

    def allowed_method(auth_method)
      name = auth_method.to_s.presence
      return if name.nil?
      return name if IdentityLink::METHODS.include?(name)

      nil
    end
  end
end
