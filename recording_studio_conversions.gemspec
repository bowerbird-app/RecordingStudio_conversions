# frozen_string_literal: true

require_relative "lib/recording_studio_conversions/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_conversions"
  spec.version     = RecordingStudioConversions::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_conversions"
  spec.summary     = "Provider-neutral conversion occurrences for Recording Studio"
  spec.description = "Records conversion occurrences from Recording Studio Users, Stripe, and Views " \
                     "events, and declares provider field, consent, channel, and age contracts."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_conversions"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_conversions/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
  spec.add_dependency "recording_studio_views", "~> 0.3.0"
end
