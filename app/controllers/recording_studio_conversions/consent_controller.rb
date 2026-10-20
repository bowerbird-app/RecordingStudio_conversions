# frozen_string_literal: true

module RecordingStudioConversions
  class ConsentController < ApplicationController
    def create
      visitor_id = VisitorId.from_request(request)
      return render json: { "visitor" => "missing" } if visitor_id.blank?
      return render json: { "error" => "malformed" }, status: :bad_request unless consent_params?

      record_answer(visitor_id)
      render json: PublicConfig.consent_response(view_context, visitor_id)
    end

    private

    def consent_params?
      params[:category].present? && !params[:granted].nil?
    end

    def record_answer(visitor_id)
      ConsentLedger.record!(
        visitor_id: visitor_id,
        category: params[:category].to_s,
        granted: ActiveModel::Type::Boolean.new.cast(params[:granted]),
        user_id: linked_user_id,
        provenance: provenance
      )
    end

    def provenance
      raw = params[:provenance]
      source = raw.respond_to?(:[]) ? raw[:source] : nil
      { "source" => source.to_s.presence || "browser" }
    end

    def linked_user_id
      user = Current.actor if defined?(Current)
      user&.id
    end
  end
end
