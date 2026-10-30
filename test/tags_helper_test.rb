# frozen_string_literal: true

require "test_helper"
require File.expand_path("../app/helpers/recording_studio_conversions/tags_helper", __dir__)

class TagsHelperTest < Minitest::Test
  def setup
    @helper = Object.new
    @helper.extend(RecordingStudioConversions::TagsHelper)
  end

  def test_tracking_mounted_is_false_without_the_route_helper
    refute @helper.tracking_mounted?
  end

  def test_tracking_mounted_is_false_without_collection_path
    @helper.define_singleton_method(:recording_studio_conversions) { Object.new }

    refute @helper.tracking_mounted?
  end

  def test_tracking_mounted_is_true_when_collection_path_exists
    routes = Object.new
    routes.define_singleton_method(:collection_path) { "/recording_studio_conversions/collection" }
    @helper.define_singleton_method(:recording_studio_conversions) { routes }

    assert @helper.tracking_mounted?
  end
end
