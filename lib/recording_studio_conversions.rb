# frozen_string_literal: true

require "recording_studio"
require "recording_studio_conversions/version"
require "recording_studio_conversions/engine"
require "recording_studio_conversions/configuration"
require "recording_studio_conversions/capabilities/example"

module RecordingStudioConversions
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
