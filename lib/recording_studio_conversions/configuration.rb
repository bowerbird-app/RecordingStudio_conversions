# frozen_string_literal: true

module RecordingStudioConversions
  class Configuration
    SUPPORTED_SCHEMA_VERSION = 1
    FAILED_EVENT = "failed.recording_studio_conversions"
    UNUSABLE_EVENT = "unusable_envelope.recording_studio_conversions"

    Subscription = Data.define(:source_name, :canonical_name, :id_key)

    attr_accessor :raise_errors, :user_class_name
    attr_reader :hooks, :subscriptions, :rules

    def initialize
      assign_defaults
      register_sources
    end

    def assign_defaults
      @hooks = RecordingStudio::Hooks.new
      @raise_errors = false
      @user_class_name = "User"
      @subscriptions = []
      @rules = []
    end

    def register_sources
      subscribe "registration.completed.recording_studio_user", as: "users.registered", id_key: :user_id
      subscribe "trial_started.recording_studio_stripe", as: "stripe.trial_started", id_key: :id
      subscribe "invoice_paid.recording_studio_stripe", as: "stripe.invoice_paid", id_key: :id
      subscribe "page_view.recorded.recording_studio_views", as: "views.recorded", id_key: :page_view_id
    end

    def subscribe(source_name, as:, id_key:)
      subscriptions << Subscription.new(source_name.to_s, as.to_s, id_key.to_sym)
    end

    def conversion(key, &)
      rules << Rule.build(key, &)
    end

    def clear_rules!
      @rules = []
    end

    def to_h
      {
        raise_errors: raise_errors,
        user_class_name: user_class_name,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end
  end
end
