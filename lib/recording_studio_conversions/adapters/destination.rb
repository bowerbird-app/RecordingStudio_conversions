# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # A host-enabled provider. Option values stay on the object. to_h, inspect,
    # and pretty_print publish the option keys only, so an access token is not
    # copied into diagnostics. to_h uses adapter_key so the hash matches the
    # member name and can be passed back to Destination.new with options.
    Destination = Data.define(:key, :adapter_key, :options) do
      def to_h
        { key: key, adapter_key: adapter_key }
      end

      def inspect
        "#<#{self.class.name} key=#{key.inspect} adapter_key=#{adapter_key.inspect} options=#{redacted_options}>"
      end

      def pretty_print(printer)
        printer.text(inspect)
      end

      def redacted_options
        pairs = options.keys.map { |option| "#{option}: [REDACTED]" }
        "{#{pairs.join(', ')}}"
      end
    end
  end
end
