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

    # Current is set by Root Switchable's before_action. An engine request does
    # not run that hook, so read the existing encrypted cookie. Never call
    # DeviceKey.fetch: that writes the cookie.
    def from_request(request)
      found = current
      return found if found.present?

      read_existing_cookie(request)
    end

    def read_existing_cookie(request)
      name = cookie_name
      return if name.nil? || request.nil?

      value = request.cookie_jar.encrypted[name].presence
      remember(value)
      value
    rescue StandardError
      nil
    end

    def remember(value)
      return if value.blank?
      return unless defined?(RecordingStudio::RootSwitchable::Current)

      RecordingStudio::RootSwitchable::Current.device_key = value
    end

    def cookie_name
      config = root_switchable_configuration
      return if config.nil?
      return config.device_key_cookie_name if config.respond_to?(:device_key_cookie_name)

      nil
    end

    def root_switchable_configuration
      return unless defined?(RecordingStudioRootSwitchable)
      return unless RecordingStudioRootSwitchable.respond_to?(:configuration)

      RecordingStudioRootSwitchable.configuration
    end
  end
end
