# frozen_string_literal: true

module RecordingStudioConversions
  class CollectionController < ApplicationController
    rate_limit to: 60, within: 1.minute, only: :create, store: RateLimitStore

    def create
      outcome = Collector.call(request: request, payload: json_payload, user: linked_user)
      if outcome["error"]
        render json: { "error" => "malformed" }, status: :bad_request
      else
        render json: outcome
      end
    end

    private

    def json_payload
      parsed = request.request_parameters.except(:controller, :action, :format)
      return parsed if parsed.present?

      body = request.raw_post
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def linked_user
      SignedInActor.resolve(self)
    end
  end
end
