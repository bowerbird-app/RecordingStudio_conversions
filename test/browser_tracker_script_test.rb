# frozen_string_literal: true

require "test_helper"
require "open3"

class BrowserTrackerScriptTest < Minitest::Test
  TRACKER = File.expand_path("../app/assets/javascripts/recording_studio_conversions/tracker.js", __dir__)
  NODE_TEST = File.expand_path("browser_tracker_node_test.js", __dir__)

  def test_tracker_script_covers_consent_turbo_and_duplicate_init
    output, status = Open3.capture2e("node", NODE_TEST, TRACKER)

    assert status.success?, output
    assert_includes output, "browser tracker script ok"
  end

  def test_tracker_source_has_no_provider_pixel_or_cookie_write
    source = File.read(TRACKER)

    refute_includes source, "document.cookie ="
    refute_includes source, "fbq"
    refute_includes source, "gtag"
    refute_includes source, "ttq"
    refute_includes source, "page_view"
    refute_includes source, "fbclid"
  end
end
