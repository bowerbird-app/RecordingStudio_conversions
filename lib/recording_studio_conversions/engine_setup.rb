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
  end
end
