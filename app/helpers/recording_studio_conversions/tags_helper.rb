# frozen_string_literal: true

module RecordingStudioConversions
  # The host calls this from a layout. Nothing injects it on its own.
  module TagsHelper
    def recording_studio_conversions_tags
      return "".html_safe unless tracking_mounted?

      tracker_element + tracker_script
    end

    def tracker_element
      tag.div("", id: "recording-studio-conversions", hidden: true, data: tracker_data)
    end

    def tracker_data
      { recording_studio_conversions_config: PublicConfig.json(self) }
    end

    def tracker_script
      javascript_include_tag("recording_studio_conversions/tracker", defer: true, "data-turbo-track": "reload")
    end

    def tracking_mounted?
      respond_to?(:recording_studio_conversions) && recording_studio_conversions.respond_to?(:collection_path)
    rescue StandardError
      false
    end
  end
end
