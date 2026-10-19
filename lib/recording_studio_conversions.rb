# frozen_string_literal: true

require "recording_studio"
require "recording_studio_conversions/version"
require "recording_studio_conversions/engine"
require "recording_studio_conversions/configuration"
require "recording_studio_conversions/capabilities/example"
require "recording_studio_conversions/rule"
require "recording_studio_conversions/visitor_id"
require "recording_studio_conversions/user_confirmation"
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

    def reevaluate!(rule_key: nil)
      Processor.reevaluate!(rule_key: rule_key)
    end
  end
end
