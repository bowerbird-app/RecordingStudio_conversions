# frozen_string_literal: true

RecordingStudioRootSwitchable.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end

  # A symbol layout name is no longer accepted; the callable receives the controller.
  config.layout = lambda do |controller:|
    if controller.respond_to?(:devise_controller?) && controller.devise_controller?
      "application"
    else
      RecordingStudio::DEFAULT_LAYOUT
    end
  end

  config.after_switch_redirect = lambda do |controller:, return_to:, **|
    candidate_path = return_to.presence
    candidate_path = controller.main_app.root_path if candidate_path.blank?

    if internal_route?(candidate_path)
      candidate_path
    else
      controller.main_app.root_path
    end
  end

  config.scope :all_workspaces do |scope|
    scope.label = "All workspaces"
    scope.description = "Every workspace root in the dummy app."
    scope.available_roots = lambda do |actor:, **|
      Workspace.order(:name).filter_map do |workspace|
        recording = RecordingStudio.root_recording_for(workspace)
        next unless recording
        next unless actor && RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

        recording
      end
    end
    scope.access_check = lambda do |actor:, recording:, **|
      RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)
    end

    scope.default_root = lambda do |roots:, **|
      roots.first
    end
  end
end

def internal_route?(path)
  routes = [
    Rails.application.routes,
    RecordingStudioRootSwitchable::Engine.routes
  ]

  routes.any? do |route_set|
    route_set.recognize_path(path, method: :get)
    true
  rescue ActionController::RoutingError
    false
  end
end
