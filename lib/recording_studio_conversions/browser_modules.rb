# frozen_string_literal: true

module RecordingStudioConversions
  # Provider module files stay off the asset path. The controller serves one
  # only after consent, and only when an enabled adapter registered that name.
  module BrowserModules
    module_function

    def find(name)
      return if name.blank?

      directories.each do |directory|
        path = directory.join("#{name}.js")
        return path if path.file?
      end
      nil
    end

    def directories
      roots = []
      roots << host_directory if host_directory
      roots << RecordingStudioConversions::Engine.root.join("lib/recording_studio_conversions/browser_modules")
      roots
    end

    def host_directory
      return unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      Rails.root.join("lib/recording_studio_conversions/browser_modules")
    end
  end
end
