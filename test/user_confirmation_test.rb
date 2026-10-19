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

  def test_assert_confirmable_skips_a_missing_class
    @configuration.user_class_name = "ConversionsMissingUser"

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
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
end
