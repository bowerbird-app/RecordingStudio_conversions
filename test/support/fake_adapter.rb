# frozen_string_literal: true

class FakeAdsAdapter < RecordingStudioConversions::Adapters::Base
  key :fake

  consent category: :advertising, collection: true, delivery: true
  delivery_channels :server, :browser
  max_event_age 7.days
  browser_module "fake-ads"

  conversion_event :trial, as: "StartTrial"
  conversion_event :purchase, as: "Purchase"
  conversion_event :first_purchase, as: "Subscribe"

  attribution do
    field :click_id,
          source: :query_parameter,
          required: false,
          required_for: ["stripe.invoice_paid"],
          alternatives: [:backup_click_id],
          transform: :strip,
          capture: :request,
          retention: 90.days,
          sensitivity: :identifier,
          events: ["stripe.trial_started", "stripe.invoice_paid"],
          channels: [:server]

    field :backup_click_id,
          source: :query_parameter,
          required: false,
          sensitivity: :identifier,
          channels: [:server]

    field :browser_id,
          source: :cookie,
          required: false,
          sensitivity: :identifier,
          channels: [:browser]
  end

  identity do
    field :external_id,
          source: :user,
          required: true,
          sensitivity: :identifier,
          capture: :later
  end
end

class ServerOnlyAdapter < RecordingStudioConversions::Adapters::Base
  key :server_only

  consent category: :analytics, collection: false, delivery: true
  delivery_channels :server

  attribution do
    field :ref_id,
          source: :query_parameter,
          required: false,
          sensitivity: :public
  end
end
