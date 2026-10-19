# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Delivery is a later milestone. These are instance methods so an adapter
    # can be built with one destination and read that destination's options
    # when deliver runs. Calling one before then raises.
    module Delivery
      def build_payload(*)
        unimplemented(__method__)
      end

      def deliver(*)
        unimplemented(__method__)
      end

      def normalize_error(*)
        unimplemented(__method__)
      end

      def dedup_id_for(*)
        unimplemented(__method__)
      end

      private

      def unimplemented(name)
        raise NotImplementedError, "#{self.class} must implement ##{name}"
      end
    end
  end
end
