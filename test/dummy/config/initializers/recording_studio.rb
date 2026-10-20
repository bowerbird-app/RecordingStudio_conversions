# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  config.recordable_types = [ "Workspace", "Folder", "Page" ]

  # Require each configured ActiveRecord type to call recording_studio_recordable.
  config.require_recordable_declarations = true

  # Shown in the shared default layout title fallback.
  config.app_name = "Addon Template" if config.respond_to?(:app_name=)

  # Engine collection and consent call this with the controller. A zero-arity
  # lambda still works for other Recording Studio callers, but it cannot see
  # the request. Current.actor is unset there: this engine does not run
  # ApplicationController, and Recording Studio Users does not set it.
  config.actor = lambda do |controller = nil|
    actor = Current.actor
    if actor.nil? && !controller.nil? && controller.respond_to?(:current_user)
      actor = controller.current_user
    end
    actor
  end

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup
end
