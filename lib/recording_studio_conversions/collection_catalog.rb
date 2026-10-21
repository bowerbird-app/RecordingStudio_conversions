# frozen_string_literal: true

module RecordingStudioConversions
  # Declared fields the collector is allowed to read. Personal values are excluded.
  module CollectionCatalog
    Entry = Data.define(:adapter, :field)
    BROWSER_SOURCES = %i[query_parameter cookie].freeze
    SERVER_SOURCES = %i[request session resolver customer workspace event].freeze

    module_function

    def browser_fields
      entries.select { |entry| BROWSER_SOURCES.include?(entry.field.source) }
    end

    def server_fields
      entries.select { |entry| SERVER_SOURCES.include?(entry.field.source) }
    end

    def find(provider, name)
      entries.find { |entry| entry.adapter.key.to_s == provider.to_s && entry.field.name.to_s == name.to_s }
    end

    def entries
      RecordingStudioConversions.configuration.enabled_adapters.flat_map do |adapter|
        next [] unless adapter.consent.collection

        adapter.fields.filter_map { |field| entry_for(adapter, field) }
      end
    end

    def entry_for(adapter, field)
      return if field.capture == :later
      return if field.sensitivity == :personal

      Entry.new(adapter, field)
    end

    def modules_for(granted_categories)
      allowed = Array(granted_categories).map(&:to_sym)
      RecordingStudioConversions.configuration.enabled_adapters.filter_map do |adapter|
        name = adapter.browser_module
        next if name.blank?
        next unless adapter.consent.collection
        next unless allowed.include?(adapter.consent.category)

        name
      end
    end
  end
end
