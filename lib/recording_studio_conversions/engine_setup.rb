# frozen_string_literal: true

module RecordingStudioConversions
  # Layout helper and log filtering, kept off Engine so that class stays small.
  module EngineSetup
    def self.extended(engine)
      engine.initializer "recording_studio_conversions.helper" do
        ActiveSupport.on_load(:action_controller_base) do
          helper RecordingStudioConversions::TagsHelper
        end
      end

      engine.initializer "recording_studio_conversions.filter_parameters" do |app|
        app.config.filter_parameters += [/\Avalue\z/, /\Avisitor_id\z/]
      end
    end

    def load_yaml_config(app)
      return unless app.respond_to?(:config_for)
      return if yaml_config_missing?(app)

      yaml = app.config_for(:recording_studio_conversions)
      RecordingStudioConversions.configuration.merge!(yaml) if yaml.respond_to?(:each)
    rescue Psych::Exception
      nil
    rescue RuntimeError => e
      raise unless rails_yaml_config_error?(e)
    end

    private

    def yaml_config_missing?(app)
      return false unless app.respond_to?(:paths)

      config_root = app.paths["config"]&.existent&.first
      return false if config_root.blank?

      !File.exist?(File.join(config_root, "recording_studio_conversions.yml"))
    end

    def rails_yaml_config_error?(error)
      message = error.message.to_s
      message.include?("YAML syntax error occurred while parsing") ||
        message.include?("Could not load configuration. No such file")
    end
  end
end
