# frozen_string_literal: true

module RecordingStudioConversions
  class ConfigurationError < StandardError; end

  # Hosts confirm accounts with Devise :confirmable. created_at is earlier
  # than OTP verification, so confirmed? is the verification signal.
  module UserConfirmation
    module_function

    def lookup(user_id)
      return [:missing, nil] if user_id.blank?

      user = user_class.find_by(id: user_id)
      return [:missing, nil] if user.nil?
      return [:found, nil] unless user.confirmed?

      [:found, user.confirmed_at]
    end

    def assert_confirmable!
      klass = user_class
      return if klass.method_defined?(:confirmed?)

      raise ConfigurationError, "#{klass.name} must implement confirmed?. " \
                                "Run bin/rails generate recording_studio_user:migrations " \
                                "and enable Devise :confirmable."
    end

    def user_class_name
      if defined?(RecordingStudioUser) && RecordingStudioUser.respond_to?(:config)
        RecordingStudioUser.config.user_class_name.to_s
      else
        RecordingStudioConversions.configuration.user_class_name.to_s
      end
    end

    def user_class
      name = user_class_name
      if name.empty?
        raise ConfigurationError, "Set RecordingStudioConversions.configuration.user_class_name " \
                                  "or load RecordingStudioUser"
      end

      name.constantize
    end
  end
end
