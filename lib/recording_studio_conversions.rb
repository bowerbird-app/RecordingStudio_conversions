# frozen_string_literal: true

require "recording_studio"
require "recording_studio_conversions/version"
require "recording_studio_conversions/engine_setup"
require "recording_studio_conversions/engine"
require "recording_studio_conversions/adapters"
require "recording_studio_conversions/provider_configuration"
require "recording_studio_conversions/configuration"
require "recording_studio_conversions/capabilities/example"
require "recording_studio_conversions/rule"
require "recording_studio_conversions/visitor_id"
require "recording_studio_conversions/user_confirmation"
require "recording_studio_conversions/consent_ledger"
require "recording_studio_conversions/collection_catalog"
require "recording_studio_conversions/browser_modules"
require "recording_studio_conversions/browser_receipt"
require "recording_studio_conversions/attribution_values"
require "recording_studio_conversions/attribution_store"
require "recording_studio_conversions/identity_linker"
require "recording_studio_conversions/attribution_policy"
require "recording_studio_conversions/signed_in_actor"
require "recording_studio_conversions/rate_limit_store"
require "recording_studio_conversions/collector"
require "recording_studio_conversions/public_config"
require "recording_studio_conversions/envelope_properties"
require "recording_studio_conversions/envelope"
require "recording_studio_conversions/occurrence_writer"
require "recording_studio_conversions/processor"

module RecordingStudioConversions
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    # Rule keys are checked here, not during register or configure, so a later
    # initializer can still add the rule. The engine runs this once from
    # config.after_initialize.
    def check!
      configuration.adapters.check!(subscriptions: configuration.subscriptions, rules: configuration.rules)
    end

    def install!
      uninstall!
      @tokens = configuration.subscriptions.map do |subscription|
        ActiveSupport::Notifications.subscribe(subscription.source_name) do |*args|
          Processor.call(subscription, args.last)
        end
      end
    end

    def uninstall!
      Array(@tokens).each { |token| ActiveSupport::Notifications.unsubscribe(token) }
      @tokens = []
    end

    def record_acquisition_user!(root_recording_id:, user_id:)
      AcquisitionSubject.record!(root_recording_id: root_recording_id, user_id: user_id)
    end

    def record_consent!(visitor_id:, category:, granted:, user_id: nil, provenance: { "source" => "host" })
      ConsentLedger.record!(
        visitor_id: visitor_id, category: category, granted: granted, user_id: user_id, provenance: provenance
      )
    end

    def attribution_for(root_recording_id:)
      AttributionStore.for_root(root_recording_id)
    end

    def delete_attribution_for_user!(user_id)
      AttributionStore.delete_for_user!(user_id)
    end

    def delete_attribution_for_root!(root_recording_id)
      AttributionStore.delete_for_root!(root_recording_id)
    end

    def reevaluate!(rule_key: nil)
      Processor.reevaluate!(rule_key: rule_key)
    end
  end
end
