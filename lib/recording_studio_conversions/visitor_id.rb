# frozen_string_literal: true

module RecordingStudioConversions
  # The only visitor id is Root Switchable's device key. This does not call
  # DeviceKey.fetch, which would write that gem's encrypted cookie.
  module VisitorId
    module_function

    def current
      return unless defined?(RecordingStudio::RootSwitchable::Current)

      RecordingStudio::RootSwitchable::Current.device_key.presence
    end
  end
end
