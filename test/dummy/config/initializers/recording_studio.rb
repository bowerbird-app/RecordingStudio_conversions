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

  # Hosts must set authorize_write. Writes fail closed: a missing
  # authorize_write raises AuthorizationError; a missing actor raises
  # ActorRequired. Keep writes closed to this callback.
  # create_root_recording! calls this with recording, root_recording, and
  # parent_recording all nil. A persisted user may start a root recordable.
  # Later writes still need edit (or admin for an access grant) on that root.
  # Access grant/bootstrap writes go through Accessible's AccessCreationContext
  # (same path as grant_access / bootstrap_owner_access!), not a logged-in check.
  config.authorize_write = lambda { |actor:, root_recording:, recordable:, **context|
    next false unless actor.is_a?(User) && actor.persisted?

    if root_recording.nil? && context[:recording].nil? && context[:parent_recording].nil?
      next RecordingStudio.root_allowed?(recordable)
    end

    next false unless root_recording

    if defined?(RecordingStudio::Access) && recordable.is_a?(RecordingStudio::Access)
      next true if RecordingStudioAccessible::AccessCreationContext.allowed?

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: root_recording,
        role: :admin
      )
    else
      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: root_recording,
        role: :edit
      )
    end
  }

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup
end
