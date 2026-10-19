# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_conversions.gemspec
gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.7.0"
gem "recording_studio_views", github: "bowerbird-app/RecordingStudio_views", tag: "v0.3.0"
# Views 0.3 depends on Logs, which is not published to RubyGems.
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.4.0"
# Stripe 0.13 is the contract for DomainEvent#instrument_payload. require: false
# keeps that engine, and the migrations it appends, out of boot. The other pins
# exist because Stripe's gemspec needs them and they are not published to RubyGems.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.196", require: false
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.18.0", require: false
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.2.0", require: false
gem "recording_studio_stripe", github: "bowerbird-app/RecordingStudio_stripe", tag: "v0.13.0", require: false
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.11.0", require: false

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
