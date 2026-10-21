# frozen_string_literal: true

# Host-only demo adapter. Not part of the gem. Required from the dummy
# initializer so development reload does not treat it as an app/ class.
# Enables the dummy inspector to collect fbclid and utm_source after consent.
class DummyAdsAdapter < RecordingStudioConversions::Adapters::Base
  key :dummy_ads

  consent category: :advertising, collection: true, delivery: false
  delivery_channels :server

  attribution do
    field :fbclid, source: :query_parameter, required: false, sensitivity: :identifier, retention: 30.days
    field :utm_source, source: :query_parameter, required: false, sensitivity: :identifier, retention: 30.days
    field :utm_medium, source: :query_parameter, required: false, sensitivity: :identifier
    field :utm_campaign, source: :query_parameter, required: false, sensitivity: :identifier
  end
end
