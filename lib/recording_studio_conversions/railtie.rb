# frozen_string_literal: true

module RecordingStudioConversions
  class Railtie < Rails::Railtie
    initializer "recording_studio_conversions.subscribe" do
      config.to_prepare { RecordingStudioConversions.install! }
    end
  end
end
