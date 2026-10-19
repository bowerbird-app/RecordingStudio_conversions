# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # A host-enabled provider. Option values stay on the object. inspect, to_s,
    # and pretty_print publish option keys only. to_h omits option values.
    # deconstruct, deconstruct_keys, and Marshal.dump carry the raw options, so
    # never cache, log, or serialize a destination.
    # Destination.new(**destination.to_h, options:) round-trips when the caller
    # passes options back in.
    Destination = Data.define(:key, :adapter_key, :options) do
      def to_h
        { key: key, adapter_key: adapter_key }
      end

      def inspect
        "#<#{self.class.name} key=#{key.inspect} adapter_key=#{adapter_key.inspect} options=#{redacted_options}>"
      end

      def to_s = inspect

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
