# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_conversions.gemspec
gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"
gem "recording_studio_views", github: "bowerbird-app/RecordingStudio_views", tag: "v0.12.0"
# Views depends on Logs, which is not published to RubyGems.
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.3"
# Stripe DomainEvent#instrument_payload still publishes integer amount from
# amount_paid. require: false keeps that engine, and the migrations it appends,
# out of boot. The other pins exist because Stripe's gemspec needs them and they
# are not published to RubyGems.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.341", require: false
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.24.1", require: false
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.7.2", require: false
gem "recording_studio_stripe", github: "bowerbird-app/RecordingStudio_stripe", tag: "v0.18.0", require: false
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.2", require: false

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
