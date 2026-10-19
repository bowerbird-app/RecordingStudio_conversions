# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioConversions::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(user_class_name: "Account", raise_errors: true)

    assert_equal "Account", @configuration.user_class_name
    assert_equal true, @configuration.raise_errors
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", api_key: "ignored", user_class_name: "Account")

    refute_respond_to @configuration, :unknown_key
    refute_respond_to @configuration, :api_key
    assert_equal "Account", @configuration.user_class_name
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:user_class_name], @configuration.user_class_name
    assert_equal original[:raise_errors], @configuration.raise_errors
  end

  def test_initialize_defaults_the_user_class_and_does_not_raise
    configuration = RecordingStudioConversions::Configuration.new

    assert_equal "User", configuration.user_class_name
    assert_equal false, configuration.raise_errors
    assert_equal %w[canceled], configuration.excluded_subscription_statuses
    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_merge_accepts_string_keys
    @configuration.merge!("user_class_name" => "Account", "raise_errors" => true)

    assert_equal "Account", @configuration.user_class_name
    assert_equal true, @configuration.raise_errors
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal "User", result.fetch(:user_class_name)
    assert_equal false, result.fetch(:raise_errors)
    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
  end

  def test_configure_without_block_is_safe
    RecordingStudioConversions.configure

    assert_kind_of RecordingStudioConversions::Configuration, RecordingStudioConversions.configuration
  end
end
