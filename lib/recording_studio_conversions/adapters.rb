# frozen_string_literal: true

require_relative "adapters/consent"
require_relative "adapters/destination"
require_relative "adapters/field"
require_relative "adapters/field_coercion"
require_relative "adapters/field_options"
require_relative "adapters/declaration_support"
require_relative "adapters/declaration"
require_relative "adapters/queries"
require_relative "adapters/base"
require_relative "adapters/registry"

module RecordingStudioConversions
  # Code-defined provider contracts. No adapter in this milestone performs I/O.
  module Adapters
    CHANNELS = %i[server browser].freeze
    SOURCES = %i[query_parameter cookie request session user customer workspace event resolver].freeze
    TYPES = %i[string integer boolean].freeze
    SENSITIVITIES = %i[public identifier personal].freeze
    CAPTURES = %i[request session later].freeze
    KINDS = %i[attribution identity].freeze
  end
end
