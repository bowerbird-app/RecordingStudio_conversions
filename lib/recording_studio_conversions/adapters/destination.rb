# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # A host-enabled provider. Option values stay on the object and out of to_h,
    # so an access token is not copied into diagnostics.
    Destination = Data.define(:key, :adapter_key, :options) do
      def to_h
        { key: key, adapter: adapter_key }
      end
    end
  end
end
