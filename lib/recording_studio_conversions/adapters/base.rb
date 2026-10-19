# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Declarations for one provider. Subclasses fill these in at load time.
    # Nothing here opens a network connection.
    class Base
      extend Declaration
      extend Queries
      include Delivery

      attr_reader :destination

      # destination is optional until delivery. M5 can pass it without a new signature.
      def initialize(destination: nil)
        @destination = destination
      end

      class << self
        def inherited(subclass)
          super
          subclass.send(:copy_declarations_from, self)
        end
      end

      send(:prepare_declarations)
    end
  end
end
