# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Read side of a provider contract. Extended onto Base.
    module Queries
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
        @event_names[source_of(rule)]
      end

      def sufficient?(available, event_name:, channel: nil)
        names = Array(available).map(&:to_sym)
        applicable(event_name, channel).all? { |field| field.optional_or_satisfied?(event_name, names) }
      end

      def within_age?(occurred_at, now: Time.current)
        return true if @max_event_age.nil?
        return false unless comparable_time?(occurred_at)

        occurred_at >= (now - @max_event_age)
      end

      private

      def applicable(event_name, channel)
        fields.select { |field| field.applies_to?(event_name: event_name, channel: channel) }
      end

      def source_of(rule)
        return rule.source.to_s if rule.respond_to?(:source)

        rule.to_s
      end

      def comparable_time?(value)
        value.respond_to?(:>=) && !value.is_a?(String) && !value.is_a?(Numeric)
      end
    end
  end
end
