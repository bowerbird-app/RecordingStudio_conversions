# frozen_string_literal: true

module RecordingStudioConversions
  # Public page data for the shared tracker. Destination options stay on the server.
  module PublicConfig
    module_function

    def json(view)
      JSON.generate(build(view))
    end

    def build(view)
      visitor_id = VisitorId.from_request(view.request)
      {
        "collect_url" => view.recording_studio_conversions.collection_path,
        "consent_url" => view.recording_studio_conversions.consent_path,
        "fields" => fields,
        "modules" => modules(view, visitor_id),
        "consent" => consent_map(visitor_id)
      }
    end

    def consent_response(view, visitor_id)
      {
        "visitor" => "present",
        "consent" => consent_map(visitor_id),
        "modules" => modules(view, visitor_id)
      }
    end

    def fields
      CollectionCatalog.browser_fields.map do |entry|
        {
          "provider" => entry.adapter.key.to_s,
          "name" => entry.field.name.to_s,
          "source" => entry.field.source.to_s,
          "consent_category" => entry.field.consent_category.to_s
        }
      end
    end

    def modules(view, visitor_id)
      CollectionCatalog.modules_for(granted_categories(visitor_id)).map do |name|
        { "name" => name, "src" => view.recording_studio_conversions.browser_module_path(name) }
      end
    end

    def consent_map(visitor_id)
      categories.index_with { |category| ConsentLedger.granted?(visitor_id: visitor_id, category: category) }
    end

    def granted_categories(visitor_id)
      categories.select { |category| ConsentLedger.granted?(visitor_id: visitor_id, category: category) }
    end

    def categories
      field_categories = CollectionCatalog.entries.map { |entry| entry.field.consent_category }
      module_categories = RecordingStudioConversions.configuration.enabled_adapters.filter_map do |adapter|
        adapter.consent.category if adapter.consent.collection && adapter.browser_module.present?
      end
      (field_categories + module_categories).uniq
    end
  end
end
