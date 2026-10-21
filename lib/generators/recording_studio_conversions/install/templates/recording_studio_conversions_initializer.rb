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

  # Providers are named classes Zeitwerk will not unload: a gem class, a file
  # required from this initializer, or config.autoload_lib_once. The reload
  # check runs only when reloading is on, so an app/ class raises in
  # development and passes in test and production. A class autoloaded from
  # Rails 8.1 autoload_lib is rejected in development. An anonymous class is
  # rejected. Registering the same class again is a no-op. Rule keys are
  # checked once at boot, so register the adapter before its rule if you need to.
  # An empty registry is a valid boot. to_h omits option values. inspect and
  # to_s print option keys only. deconstruct, deconstruct_keys, and Marshal.dump
  # carry raw options, so never cache, log, or serialize a destination.
  # config.register_adapter :example, ExampleAdapter
  # config.destination :example, adapter: :example

  # The default resolver reads the one acquisition user recorded with
  # RecordingStudioConversions.record_acquisition_user! after Onboarding.
  # Return nil when that user cannot be resolved. Do not return another member.
  # config.attribution_subject_resolver = lambda do |event|
  #   RecordingStudioConversions::AcquisitionSubject.for_root(event.root_recording_id)
  # end
end
