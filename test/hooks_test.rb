# frozen_string_literal: true

require "test_helper"

class HooksTest < Minitest::Test
  def test_template_does_not_ship_a_copied_hooks_class
    refute File.exist?(File.expand_path("../lib/recording_studio_conversions/hooks.rb", __dir__))
    refute defined?(RecordingStudioConversions::Hooks)
  end

  def test_configuration_hooks_are_core_recording_studio_hooks
    configuration = RecordingStudioConversions::Configuration.new

    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_engine_runs_addon_hooks_through_configuration
    called = false
    RecordingStudioConversions.configuration.hooks.after_initialize { called = true }

    initializer = RecordingStudioConversions::Engine.initializers.find do |entry|
      entry.name == "recording_studio_conversions.after_initialize"
    end
    initializer.block.call(Object.new)

    assert called
  ensure
    RecordingStudioConversions.configuration.hooks.clear!
  end
end
