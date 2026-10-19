# frozen_string_literal: true

RecordingStudioConversions.configure do |config|
  # Used only when RecordingStudioUser is not loaded. When that gem is loaded,
  # RecordingStudioUser.config.user_class_name wins, and a different value here warns at boot.
  config.user_class_name = "User"
  config.raise_errors = false

  # Policy: a paid invoice on a canceled subscription is not a conversion.
  # Blank or missing subscription_status stays unknown and can still match.
  # incomplete_expired and unpaid are not excluded unless you add them.
  # config.excluded_subscription_statuses = %w[canceled]
end
