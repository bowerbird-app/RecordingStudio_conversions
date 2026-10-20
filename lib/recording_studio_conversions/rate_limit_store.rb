# frozen_string_literal: true

module RecordingStudioConversions
  # Rails rate_limit captures its store when the controller class loads.
  # This object forwards to Rails.cache, which a host must set to a real
  # store. Tests assign a MemoryStore here because the test cache is :null_store.
  module RateLimitStore
    class << self
      attr_accessor :store

      def increment(name, amount = 1, **)
        current.increment(name, amount, **)
      end

      def current
        store || Rails.cache
      end
    end
  end
end
