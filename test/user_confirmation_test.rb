# frozen_string_literal: true

require "test_helper"
require "active_record"

class UserConfirmationTest < Minitest::Test
  TEMPORARY_CLASSES = %i[ConversionsConfirmableUser ConversionsPlainUser ConversionsUserWithoutTable].freeze

  def setup
    @previous = RecordingStudioConversions.instance_variable_get(:@configuration)
    @configuration = RecordingStudioConversions::Configuration.new
    RecordingStudioConversions.instance_variable_set(:@configuration, @configuration)
  end

  def teardown
    RecordingStudioConversions.instance_variable_set(:@configuration, @previous)
    TEMPORARY_CLASSES.each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end

  def test_assert_confirmable_warns_when_the_class_name_is_unresolved
    @configuration.user_class_name = "ConversionsMissingUser"
    warnings = []
    confirmation = RecordingStudioConversions::UserConfirmation

    confirmation.stub(:eager_load?, false) do
      confirmation.stub(:warn_boot, ->(message) { warnings << message }) do
        assert_nil confirmation.assert_confirmable!
      end
    end

    assert_match("ConversionsMissingUser", warnings.join)
  end

  def test_assert_confirmable_raises_when_eager_load_cannot_resolve_the_class
    @configuration.user_class_name = "ConversionsMissingUser"
    confirmation = RecordingStudioConversions::UserConfirmation

    confirmation.stub(:eager_load?, true) do
      error = assert_raises(RecordingStudioConversions::ConfigurationError) do
        confirmation.assert_confirmable!
      end
      assert_match("ConversionsMissingUser", error.message)
    end
  end

  def test_assert_confirmable_skips_a_blank_class_name
    @configuration.user_class_name = ""

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
  end

  def test_assert_confirmable_skips_when_the_database_does_not_exist
    Object.const_set(:ConversionsUserWithoutTable, Class.new do
      def self.table_exists?
        raise ActiveRecord::NoDatabaseError
      end
    end)
    @configuration.user_class_name = "ConversionsUserWithoutTable"

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
  end

  def test_assert_confirmable_skips_before_the_table_exists
    Object.const_set(:ConversionsUserWithoutTable, Class.new do
      def self.table_exists?
        false
      end
    end)
    @configuration.user_class_name = "ConversionsUserWithoutTable"

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
  end

  def test_assert_confirmable_accepts_a_class_that_implements_confirmed
    Object.const_set(:ConversionsConfirmableUser, Class.new do
      def self.table_exists?
        true
      end

      def confirmed?
        true
      end

      def self.column_names
        %w[id confirmed_at]
      end
    end)
    @configuration.user_class_name = "ConversionsConfirmableUser"

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
  end

  def test_assert_confirmable_raises_when_the_loaded_class_lacks_confirmed
    Object.const_set(:ConversionsPlainUser, Class.new do
      def self.table_exists?
        true
      end
    end)
    @configuration.user_class_name = "ConversionsPlainUser"

    error = assert_raises(RecordingStudioConversions::ConfigurationError) do
      RecordingStudioConversions::UserConfirmation.assert_confirmable!
    end
    assert_includes error.message, "confirmed?"
  end

  def test_assert_confirmable_requires_the_confirmed_at_column
    Object.const_set(:ConversionsConfirmableUser, Class.new do
      def self.table_exists?
        true
      end

      def self.column_names
        %w[id]
      end

      def confirmed?
        true
      end
    end)
    @configuration.user_class_name = "ConversionsConfirmableUser"

    error = assert_raises(RecordingStudioConversions::ConfigurationError) do
      RecordingStudioConversions::UserConfirmation.assert_confirmable!
    end
    assert_includes error.message, "confirmed_at"
  end

  def test_a_loaded_users_gem_warns_when_user_class_name_disagrees
    configured = Module.new do
      def self.config
        Struct.new(:user_class_name).new("Account")
      end
    end
    Object.const_set(:RecordingStudioUser, configured)
    @configuration.user_class_name = "Member"
    warnings = []
    confirmation = RecordingStudioConversions::UserConfirmation
    confirmation.instance_variable_set(:@mismatch_warned, nil)

    confirmation.stub(:warn_boot, ->(message) { warnings << message }) do
      assert_equal "Account", confirmation.user_class_name
    end

    assert_match("Member", warnings.join)
    assert_match("Account", warnings.join)
  ensure
    Object.send(:remove_const, :RecordingStudioUser) if Object.const_defined?(:RecordingStudioUser, false)
    RecordingStudioConversions::UserConfirmation.instance_variable_set(:@mismatch_warned, nil)
  end
end
