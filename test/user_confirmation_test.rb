# frozen_string_literal: true

require "test_helper"
require "active_record"

class UserConfirmationTest < Minitest::Test
  def setup
    @previous = RecordingStudioConversions.configuration
    @configuration = RecordingStudioConversions::Configuration.new
    RecordingStudioConversions.configuration = @configuration
  end

  def teardown
    RecordingStudioConversions.configuration = @previous
  end

  def test_assert_confirmable_warns_when_the_class_name_is_unresolved
    @configuration.user_class_name = "ConversionsMissingUser"
    warnings = []
    confirmation = RecordingStudioConversions::UserConfirmation

    confirmation.stub(:eager_load?, false) do
      confirmation.stub(:warn_boot, ->(message) { warnings << message }) do
        confirmation.stub(:load_user_class, ->(_name) {}) do
          assert_nil confirmation.assert_confirmable!
        end
      end
    end

    assert_match("ConversionsMissingUser", warnings.join)
  end

  def test_assert_confirmable_raises_when_eager_load_cannot_resolve_the_class
    @configuration.user_class_name = "ConversionsMissingUser"
    confirmation = RecordingStudioConversions::UserConfirmation

    confirmation.stub(:eager_load?, true) do
      confirmation.stub(:load_user_class, ->(_name) {}) do
        error = assert_raises(RecordingStudioConversions::ConfigurationError) do
          confirmation.assert_confirmable!
        end
        assert_match("ConversionsMissingUser", error.message)
      end
    end
  end

  def test_assert_confirmable_skips_a_blank_class_name
    @configuration.user_class_name = ""

    assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
  end

  def test_assert_confirmable_skips_when_the_database_does_not_exist
    klass = Class.new do
      def self.table_exists?
        raise ActiveRecord::NoDatabaseError
      end
    end
    @configuration.user_class_name = "ConversionsUserWithoutTable"

    RecordingStudioConversions::UserConfirmation.stub(:load_user_class, klass) do
      assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
    end
  end

  def test_assert_confirmable_skips_before_the_table_exists
    klass = Class.new do
      def self.table_exists?
        false
      end
    end
    @configuration.user_class_name = "ConversionsUserWithoutTable"

    RecordingStudioConversions::UserConfirmation.stub(:load_user_class, klass) do
      assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
    end
  end

  def test_assert_confirmable_accepts_a_class_that_implements_confirmed
    klass = Class.new do
      def self.table_exists?
        true
      end

      def confirmed?
        true
      end

      def self.column_names
        %w[id confirmed_at]
      end
    end
    @configuration.user_class_name = "ConversionsConfirmableUser"

    RecordingStudioConversions::UserConfirmation.stub(:load_user_class, klass) do
      assert_nil RecordingStudioConversions::UserConfirmation.assert_confirmable!
    end
  end

  def test_assert_confirmable_raises_when_the_loaded_class_lacks_confirmed
    klass = Class.new do
      def self.name
        "ConversionsPlainUser"
      end

      def self.table_exists?
        true
      end
    end
    @configuration.user_class_name = "ConversionsPlainUser"

    error = RecordingStudioConversions::UserConfirmation.stub(:load_user_class, klass) do
      assert_raises(RecordingStudioConversions::ConfigurationError) do
        RecordingStudioConversions::UserConfirmation.assert_confirmable!
      end
    end
    assert_includes error.message, "confirmed?"
  end

  def test_assert_confirmable_requires_the_confirmed_at_column
    klass = Class.new do
      def self.name
        "ConversionsConfirmableUser"
      end

      def self.table_exists?
        true
      end

      def self.column_names
        %w[id]
      end

      def confirmed?
        true
      end
    end
    @configuration.user_class_name = "ConversionsConfirmableUser"

    error = RecordingStudioConversions::UserConfirmation.stub(:load_user_class, klass) do
      assert_raises(RecordingStudioConversions::ConfigurationError) do
        RecordingStudioConversions::UserConfirmation.assert_confirmable!
      end
    end
    assert_includes error.message, "confirmed_at"
  end

  def test_a_loaded_users_gem_warns_when_user_class_name_disagrees
    @configuration.user_class_name = "Member"
    warnings = []
    confirmation = RecordingStudioConversions::UserConfirmation
    confirmation.reset_mismatch_warning!

    confirmation.stub(:users_gem_class_name, "Account") do
      confirmation.stub(:warn_boot, ->(message) { warnings << message }) do
        assert_equal "Account", confirmation.user_class_name
      end
    end

    assert_match("Member", warnings.join)
    assert_match("Account", warnings.join)
  ensure
    RecordingStudioConversions::UserConfirmation.reset_mismatch_warning!
  end
end
