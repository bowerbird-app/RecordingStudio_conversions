# frozen_string_literal: true

module RecordingStudioConversions
  # Payload visitor_id wins. The fallback is Root Switchable's device key.
  # DeviceKey.fetch is never called, because that writes the encrypted cookie.
  module VisitorId
    module_function

    def resolve(payload)
      from_payload(payload) || current
    end

    def from_payload(payload)
      return unless payload.respond_to?(:[])

      value = payload[:visitor_id]
      value = payload["visitor_id"] if value.nil?
      value.to_s.presence
    end

    def current
      return unless defined?(RecordingStudio::RootSwitchable::Current)

      RecordingStudio::RootSwitchable::Current.device_key.presence
    end
  end
end
