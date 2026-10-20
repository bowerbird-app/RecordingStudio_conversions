# frozen_string_literal: true

class CatalogAdsAdapter < RecordingStudioConversions::Adapters::Base
  key :catalog

  consent category: :advertising, collection: true, delivery: true
  delivery_channels :server, :browser
  browser_module "fake-ads"

  attribution do
    field :click_id, source: :query_parameter, required: false, sensitivity: :identifier, retention: 30.days
    field :browser_id, source: :cookie, required: false, sensitivity: :identifier
    field :user_agent, source: :request, required: false, sensitivity: :identifier
    field :ip_address, source: :request, required: false, sensitivity: :identifier
    field :plan, source: :resolver, required: false, sensitivity: :public
    field :note, source: :session, required: false, sensitivity: :public
    field :workspace_plan, source: :workspace, required: false, sensitivity: :public
  end

  identity do
    field :email, source: :user, required: false, sensitivity: :personal, capture: :later
  end
end
