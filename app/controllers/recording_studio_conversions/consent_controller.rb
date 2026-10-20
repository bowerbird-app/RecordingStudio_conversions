# frozen_string_literal: true

module RecordingStudioConversions
  class ConsentController < ApplicationController
    rate_limit to: 60, within: 1.minute, only: :create

    def create
      visitor_id = VisitorId.from_request(request)
      return render json: { "visitor" => "missing" } if visitor_id.blank?
      return render json: { "error" => "malformed" }, status: :unprocessable_entity unless acceptable?

      record_answer(visitor_id)
      render json: PublicConfig.consent_response(view_context, visitor_id)
    end

    private

    def acceptable?
      params[:category].present? && !granted_flag.nil? && known_category?
    end

    def known_category?
      PublicConfig.categories.map(&:to_s).include?(params[:category].to_s)
    end

    def granted_flag
      case params[:granted]
      when true, "true" then true
      when false, "false" then false
      end
    end

    def record_answer(visitor_id)
      ConsentLedger.record!(
        visitor_id: visitor_id,
        category: params[:category].to_s,
        granted: granted_flag,
        user_id: SignedInActor.resolve&.id,
        provenance: { "source" => "browser" }
      )
    end
  end
end
