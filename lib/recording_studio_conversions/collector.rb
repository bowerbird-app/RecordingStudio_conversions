# frozen_string_literal: true

module RecordingStudioConversions
  # Browser collection. A conversion claim in the body is ignored.
  module Collector
    CLAIM_KEYS = %w[
      conversion occurrence_id receipt provider_dedup_id event_name amount trial payment visitor_id
    ].freeze
    FIELD_KEYS = %w[provider name value].freeze

    module_function

    def call(request:, payload:, user: nil)
      data = normalize(payload)
      return { "error" => "malformed" } if data.nil?

      visitor_id = VisitorId.from_request(request)
      claims = CLAIM_KEYS & data.keys
      return missing(claims) if visitor_id.blank?

      context = collection_context(request, user)
      recorded = AttributionStore.record(visitor_id: visitor_id, payload: data, request: request, context: context)
      IdentityLinker.from_request(visitor_id: visitor_id, user: user)
      { "recorded" => recorded, "visitor" => "present", "ignored_claims" => claims }
    end

    def missing(claims)
      { "recorded" => 0, "visitor" => "missing", "ignored_claims" => claims }
    end

    def normalize(payload)
      hash = permitted_hash(payload)
      return unless hash.is_a?(Hash)

      hash.deep_stringify_keys
    end

    def permitted_hash(payload)
      return if payload.nil?
      return permit_parameters(payload) if payload.respond_to?(:permit)
      return slice_hash(payload) if payload.is_a?(Hash)

      nil
    end

    def permit_parameters(payload)
      payload.permit(*CLAIM_KEYS.map(&:to_sym), fields: FIELD_KEYS).to_h
    end

    def slice_hash(payload)
      sliced = payload.stringify_keys.slice(*(CLAIM_KEYS + ["fields"]))
      sliced["fields"] = Array(sliced["fields"]).filter_map { |item| slice_field(item) }
      sliced
    end

    def slice_field(item)
      return unless item.is_a?(Hash)

      item.stringify_keys.slice(*FIELD_KEYS)
    end

    def collection_context(request, user)
      extra = host_context(request, user)
      {
        root_recording_id: root_recording_id,
        customer: {},
        workspace: {},
        event: {}
      }.merge(extra)
    end

    def host_context(request, user)
      resolver = RecordingStudioConversions.configuration.collection_context
      return {} if resolver.nil?

      value = resolver.call(request, user)
      value.is_a?(Hash) ? value.symbolize_keys : {}
    end

    def root_recording_id
      return unless defined?(RecordingStudio::RootSwitchable::Current)

      current = RecordingStudio::RootSwitchable::Current
      recording = current.root_recording if current.respond_to?(:root_recording)
      recording&.id
    end
  end
end
