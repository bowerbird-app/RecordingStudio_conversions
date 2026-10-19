# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Read side of a provider contract. Extended onto Base.
    module Queries
      # A timestamp this far ahead of now is clock skew, not a future event.
      FUTURE_CLOCK_SKEW = 5.minutes

      def attribution_fields
        @attribution_fields.dup.freeze
      end

      def identity_fields
        @identity_fields.dup.freeze
      end

      def fields
        (attribution_fields + identity_fields).freeze
      end

      def event_name_for(rule)
        @event_names[rule_key_of(rule)]
      end

      # channel nil applies every channel's requirements together.
      def sufficient?(available, event_name:, channel: nil)
        names = Array(available).map(&:to_sym)
        applicable(event_name, channel).all? { |field| field.optional_or_satisfied?(event_name, names) }
      end

      # Accepts Time, DateTime, or ActiveSupport::TimeWithZone. A Date raises.
      # A timestamp more than FUTURE_CLOCK_SKEW ahead of now is not within age.
      def within_age?(occurred_at, now: Time.current)
        timestamp = timestamp_for(occurred_at)
        return false if beyond_clock_skew?(timestamp, now)
        return true if @max_event_age.nil?
        return false if timestamp.nil?

        timestamp >= now - @max_event_age
      end

      private

      def applicable(event_name, channel)
        fields.select { |field| field.applies_to?(event_name: event_name, channel: channel) }
      end

      def rule_key_of(rule)
        return rule.key.to_s if rule.respond_to?(:key)

        rule.to_s
      end

      def timestamp_for(value)
        raise ArgumentError, "occurred_at must be a Time or DateTime" if plain_date?(value)
        return value if value.is_a?(Time) || time_with_zone?(value)
        return value.to_time if value.is_a?(DateTime)

        nil
      end

      def plain_date?(value)
        value.is_a?(Date) && !value.is_a?(DateTime)
      end

      def time_with_zone?(value)
        defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone)
      end

      def beyond_clock_skew?(timestamp, now)
        !timestamp.nil? && timestamp > now + FUTURE_CLOCK_SKEW
      end
    end
  end
end
