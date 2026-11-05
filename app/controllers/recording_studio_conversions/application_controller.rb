# frozen_string_literal: true

module RecordingStudioConversions
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    recording_studio_layout { RecordingStudioConversions.configuration.layout }
  end
end
