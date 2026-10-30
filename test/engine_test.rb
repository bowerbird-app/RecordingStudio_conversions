# frozen_string_literal: true

require "test_helper"
require "active_record"
require "action_controller"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioConversions.configuration
    RecordingStudioConversions.configuration = RecordingStudioConversions::Configuration.new
  end

  def teardown
    RecordingStudioConversions.configuration.hooks.clear!
    RecordingStudioConversions.configuration = @original_configuration
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    RecordingStudioConversions.configuration.hooks.before_initialize { |_engine| before_called = true }
    RecordingStudioConversions.configuration.hooks.after_initialize { |_engine| after_called = true }

    find_initializer("recording_studio_conversions.before_initialize").block.call(Object.new)
    find_initializer("recording_studio_conversions.after_initialize").block.call(Object.new)

    assert before_called
    assert after_called
  end

  def test_load_config_merges_config_sources_and_runs_on_configuration_hook
    hook_called = false
    hook_payload = nil
    RecordingStudioConversions.configuration.hooks.on_configuration do |cfg|
      hook_called = true
      hook_payload = cfg
    end

    xcfg = Struct.new(:recording_studio_conversions).new({ raise_errors: true })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { user_class_name: "Account" }
      end
    end.new(app_config)

    find_initializer("recording_studio_conversions.load_config").block.call(app)

    assert hook_called
    assert_equal RecordingStudioConversions.configuration, hook_payload
    assert_equal "Account", RecordingStudioConversions.configuration.user_class_name
    assert_equal true, RecordingStudioConversions.configuration.raise_errors
  end

  def test_load_config_handles_errors_and_each_pair_fallback
    pair_config = Class.new do
      def each_pair
        yield(:user_class_name, "Account")
      end
    end.new

    xcfg = Struct.new(:recording_studio_conversions).new(pair_config)
    app_config = Struct.new(:x).new(xcfg)

    app = Struct.new(:config) do
      def config_for(_name)
        raise "Could not load configuration. No such file - recording_studio_conversions.yml"
      end
    end.new(app_config)

    find_initializer("recording_studio_conversions.load_config").block.call(app)

    assert_equal "Account", RecordingStudioConversions.configuration.user_class_name
  end

  def test_load_config_raises_each_pair_errors
    bad_pair_config = Class.new do
      def each_pair
        raise "bad pair"
      end
    end.new

    xcfg = Struct.new(:recording_studio_conversions).new(bad_pair_config)
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { user_class_name: "Account" }
      end
    end.new(app_config)

    error = assert_raises(RuntimeError) do
      find_initializer("recording_studio_conversions.load_config").block.call(app)
    end
    assert_equal "bad pair", error.message
    assert_equal "Account", RecordingStudioConversions.configuration.user_class_name
  end

  def test_load_config_is_noop_without_config_sources
    app = Struct.new(:config).new(Object.new)

    find_initializer("recording_studio_conversions.load_config").block.call(app)

    assert_equal "User", RecordingStudioConversions.configuration.user_class_name
    assert_equal false, RecordingStudioConversions.configuration.raise_errors
  end

  def test_load_config_ignores_non_enumerable_yaml_and_merge_errors
    yaml = Object.new

    xcfg = Struct.new(:recording_studio_conversions).new({ raise_errors: true })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      attr_accessor :yaml

      def config_for(_name)
        @yaml
      end
    end.new(app_config)
    app.yaml = yaml

    find_initializer("recording_studio_conversions.load_config").block.call(app)

    assert_equal true, RecordingStudioConversions.configuration.raise_errors
  end

  def test_apply_extension_initializers_register_active_support_on_load_callbacks
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    RecordingStudioConversions::Engine.stub(:config, config_stub) do
      find_initializer("recording_studio_conversions.apply_model_extensions").block.call
      find_initializer("recording_studio_conversions.apply_controller_extensions").block.call
    end

    assert_equal 2, to_prepare_blocks.size
  end

  def test_model_extension_initializer_skips_abstract_models
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    abstract_model = Class.new do
      def self.abstract_class?
        true
      end
    end
    concrete_model = Class.new do
      def self.abstract_class?
        false
      end
    end
    applied = []

    RecordingStudioConversions::Engine.stub(:config, config_stub) do
      find_initializer("recording_studio_conversions.apply_model_extensions").block.call
    end

    RecordingStudioConversions::Engine.stub(:apply_model_extensions, ->(model) { applied << model }) do
      ActiveRecord::Base.stub(:descendants, [abstract_model, concrete_model]) do
        to_prepare_blocks.first.call
      end
    end

    assert_equal [concrete_model], applied
  end

  def test_controller_extension_initializer_applies_all_controllers
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    first_controller = Class.new
    second_controller = Class.new
    applied = []

    RecordingStudioConversions::Engine.stub(:config, config_stub) do
      find_initializer("recording_studio_conversions.apply_controller_extensions").block.call
    end

    RecordingStudioConversions::Engine.stub(:apply_controller_extensions, ->(controller) { applied << controller }) do
      ActionController::Base.stub(:descendants, [first_controller, second_controller]) do
        to_prepare_blocks.first.call
      end
    end

    assert_equal [first_controller, second_controller], applied
  end

  def test_apply_model_extensions_adds_registered_methods_once
    model_class = Class.new do
      def self.name
        "ExampleRecord"
      end
    end

    RecordingStudioConversions.configuration.hooks.extend_model(:ExampleRecord) do
      def template_extension_method
        :applied
      end
    end

    RecordingStudioConversions::Engine.apply_model_extensions(model_class)
    RecordingStudioConversions::Engine.apply_model_extensions(model_class)

    instance = model_class.new
    assert_equal :applied, instance.template_extension_method
  end

  def test_apply_controller_extensions_matches_demodulized_name
    controller_class = Class.new do
      def self.name
        "Admin::DashboardController"
      end
    end

    RecordingStudioConversions.configuration.hooks.extend_controller(:DashboardController) do
      def template_controller_extension
        :applied
      end
    end

    RecordingStudioConversions::Engine.apply_controller_extensions(controller_class)

    instance = controller_class.new
    assert_equal :applied, instance.template_controller_extension
  end

  def test_apply_extensions_flattens_compacts_and_tracks_identity
    target = Class.new
    extension = proc do
      def generated_method
        :generated
      end
    end

    RecordingStudioConversions::Engine.apply_extensions(target, [nil, [extension, extension]])

    assert_equal :generated, target.new.generated_method
    applied = target.instance_variable_get(:@recording_studio_conversions_applied_extensions)
    assert_equal true, applied.compare_by_identity?
  end

  def test_apply_extensions_returns_without_target
    assert_nil RecordingStudioConversions::Engine.apply_extensions(nil, [])
  end

  def test_extension_keys_for_includes_demodulized_name
    namespaced = Class.new do
      def self.name
        "Admin::ReportsController"
      end
    end

    expected_keys = [:"Admin::ReportsController"]
    expected_keys << :ReportsController

    assert_equal expected_keys, RecordingStudioConversions::Engine.extension_keys_for(namespaced)
  end

  def test_extension_keys_for_removes_duplicate_names
    plain = Class.new do
      def self.name
        "ReportsController"
      end
    end

    assert_equal [:ReportsController], RecordingStudioConversions::Engine.extension_keys_for(plain)
  end

  private

  def find_initializer(name)
    RecordingStudioConversions::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
