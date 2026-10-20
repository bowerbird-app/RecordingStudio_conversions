# frozen_string_literal: true

module RecordingStudioConversions
  # Browser collection. A conversion claim in the body is ignored.
  module Collector
    CLAIM_KEYS = %w[
      conversion occurrence_id receipt provider_dedup_id event_name amount trial payment visitor_id
    ].freeze

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
      return if payload.nil?

      hash = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
      return unless hash.is_a?(Hash)

      hash.deep_stringify_keys
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
