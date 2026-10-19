# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/notifications"
require "recording_studio_conversions/configuration"
require "recording_studio_conversions/rule"
require "recording_studio_conversions/envelope"
require "recording_studio_conversions/visitor_id"
require "recording_studio_conversions/user_confirmation"
require "recording_studio_conversions/occurrence"
require "recording_studio_conversions/acquisition_subject"
require "recording_studio_conversions/processor"

module RecordingStudioConversions
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
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
  end
end

require "recording_studio_conversions/railtie" if defined?(Rails::Railtie)
