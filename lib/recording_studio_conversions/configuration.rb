# frozen_string_literal: true

module RecordingStudioConversions
  class Configuration
    Subscription = Data.define(:source_name, :canonical_name)

    attr_reader :subscriptions, :rules

    def initialize
      @subscriptions = []
      @rules = []
      subscribe "registration.completed.recording_studio_user", as: "users.registered"
      subscribe "trial_started.recording_studio_stripe", as: "stripe.trial_started"
      subscribe "invoice_paid.recording_studio_stripe", as: "stripe.invoice_paid"
      subscribe "recorded.recording_studio_views", as: "views.recorded"
    end

    def subscribe(source_name, as:)
      subscriptions << Subscription.new(source_name.to_s, as.to_s)
    end

    def conversion(key, &)
      rules << Rule.build(key, &)
    end

    def clear_rules!
      @rules = []
    end
  end
end
