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
      klass = safe_user_class
      return if klass.nil?
      return unless klass.respond_to?(:table_exists?) && klass.table_exists?
      return if klass.method_defined?(:confirmed?)

      raise ConfigurationError, "#{klass.name} must implement confirmed?. " \
                                "Run bin/rails generate recording_studio_user:migrations " \
                                "and enable Devise :confirmable."
    end

    def safe_user_class
      name = user_class_name
      return if name.blank?

      name.safe_constantize
    end

    def user_class_name
      if defined?(RecordingStudioUser) && RecordingStudioUser.respond_to?(:config)
        RecordingStudioUser.config.user_class_name.to_s
      else
        RecordingStudioConversions.configuration.user_class_name.to_s
      end
    end

    def confirming_user_id(envelope, subject)
      return viewer_id(envelope) if envelope.name == "views.recorded"

      acquisition_user_id(envelope, subject)
    end

    def viewer_id(envelope)
      envelope.actor_id if envelope.actor_type == user_class_name
    end

    def acquisition_user_id(envelope, subject)
      return subject.subject_id if subject&.subject_type == user_class_name
      return envelope.actor_id if envelope.actor_type == user_class_name

      nil
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
