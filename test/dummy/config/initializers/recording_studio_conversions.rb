# frozen_string_literal: true

require_relative "../dummy_ads_adapter"

RecordingStudioConversions.configure do |config|
  config.user_class_name = "User"
end

# Dummy browser demo only. The gem ships with no destination, so this host
# adapter is what makes ?fbclid= and ?utm_source= collectable after consent.
Rails.application.config.to_prepare do
  next unless Rails.env.local?
  next if RecordingStudioConversions.configuration.adapters.registered?(:dummy_ads)

  RecordingStudioConversions.configuration.register_adapter :dummy_ads, DummyAdsAdapter
  RecordingStudioConversions.configuration.destination :dummy_ads, adapter: :dummy_ads
end
