# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  def grant_workspace_access!(actor, workspace)
    recording = RecordingStudio.root_recording_for(workspace)
    return recording if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    return recording if result.success?
    return recording if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)

    raise result.error
  end
end
