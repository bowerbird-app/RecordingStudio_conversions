# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # One declared attribution or identity field. `transform` is a name only.
    Field = Data.define(
      :name, :kind, :type, :source, :required, :required_for, :alternatives,
      :transform, :capture, :retention, :consent_category, :sensitivity, :events, :channels
    ) do
      def applies_to?(event_name:, channel:)
        event_match?(event_name) && channel_match?(channel)
      end

      def required_for?(event_name)
        return false unless event_match?(event_name)
        return true if required

        required_for.include?(event_name.to_s)
      end

      def satisfied_by?(available)
        present = Array(available).map(&:to_sym)
        ([name] + alternatives).any? { |item| present.include?(item) }
      end

      def optional_or_satisfied?(event_name, available)
        return true unless required_for?(event_name)

        satisfied_by?(available)
      end

      private

      def event_match?(event_name)
        events.empty? || events.include?(event_name.to_s)
      end

      # A nil channel applies every channel's requirements. An empty channel
      # list on the field itself means the field applies on every channel.
      def channel_match?(channel)
        return true if channel.nil? || channels.empty?

        channels.include?(channel.to_sym)
      end
    end
  end
end
