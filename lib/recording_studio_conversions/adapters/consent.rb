# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # What a provider requires before collection or delivery. A visitor's answer
    # is stored on recording_studio_conversions_consents, not here.
    Consent = Data.define(:category, :collection, :delivery) do
      def self.build(category:, collection:, delivery:)
        raise ArgumentError, "consent category is required" if category.blank?
        raise ArgumentError, "consent collection must be true or false" unless boolean?(collection)
        raise ArgumentError, "consent delivery must be true or false" unless boolean?(delivery)

        new(category.to_sym, collection, delivery)
      end

      def self.boolean?(value)
        [true, false].include?(value)
      end
    end
  end
end
