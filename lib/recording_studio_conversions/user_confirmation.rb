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
      name = user_class_name
      return if name.blank?

      klass = name.safe_constantize
      return unresolved_class!(name) if klass.nil?
      return unless table_ready?(klass)
      return if confirmable_class?(klass)

      raise ConfigurationError, confirmable_message(klass)
    end

    def confirmable_class?(klass)
      klass.method_defined?(:confirmed?) && klass.column_names.include?("confirmed_at")
    end

    def confirmable_message(klass)
      "#{klass.name} must implement confirmed? and have a confirmed_at column. " \
        "Run bin/rails generate recording_studio_user:migrations and enable Devise :confirmable."
    end

    def unresolved_class!(name)
      message = "Could not resolve conversions user class #{name.inspect}"
      raise ConfigurationError, message if eager_load?

      warn_boot(message)
      nil
    end

    def eager_load?
      rails_config&.eager_load
    end

    def rails_config
      return unless defined?(::Rails) && ::Rails.respond_to?(:application)

      ::Rails.application&.config
    end

    def warn_boot(message)
      return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

      ::Rails.logger.warn("[RecordingStudioConversions] #{message}")
    end

    def table_ready?(klass)
      klass.respond_to?(:table_exists?) && klass.table_exists?
    rescue ::ActiveRecord::NoDatabaseError, ::ActiveRecord::ConnectionNotEstablished
      false
    end

    def user_class_name
      if defined?(::RecordingStudioUser) && ::RecordingStudioUser.respond_to?(:config)
        from_users = ::RecordingStudioUser.config.user_class_name.to_s
        warn_user_class_mismatch(from_users)
        from_users
      else
        RecordingStudioConversions.configuration.user_class_name.to_s
      end
    end

    def warn_user_class_mismatch(from_users)
      configured = RecordingStudioConversions.configuration.user_class_name.to_s
      return if configured.blank? || configured == from_users
      return if @mismatch_warned

      @mismatch_warned = true
      warn_boot(
        "config.user_class_name #{configured.inspect} is ignored because " \
        "RecordingStudioUser.config.user_class_name is #{from_users.inspect}"
      )
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
