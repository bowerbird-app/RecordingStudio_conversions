# frozen_string_literal: true

module RecordingStudioConversions
  # Users keeps confirmed_at. created_at is earlier than OTP verification, so
  # it is not the verification signal.
  module UserConfirmation
    module_function

    def lookup(user_id)
      user = find_user(user_id)
      return [:missing, nil] if user.nil?

      confirmed_at = user.respond_to?(:confirmed_at) ? user.confirmed_at : nil
      [:found, confirmed_at]
    end

    def find_user(user_id)
      return if user_id.blank?

      user_class&.find_by(id: user_id)
    end

    def user_class
      if defined?(RecordingStudioUser) && RecordingStudioUser.respond_to?(:config)
        RecordingStudioUser.config.user_class
      elsif defined?(::User)
        ::User
      end
    end
  end
end
