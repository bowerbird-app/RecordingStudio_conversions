# frozen_string_literal: true

module RecordingStudioConversions
  # Historical observations. Selection does not collapse them to a last click.
  module AttributionStore
    Result = Data.define(:status, :subject, :observations)
    Capture = Data.define(:entry, :visitor_id, :value, :request, :context, :captured_at)

    module_function

    def record(visitor_id:, payload:, request:, context:)
      recorded = 0
      recorded += record_browser(visitor_id, payload, request, context)
      recorded += record_server(visitor_id, request, context)
      recorded
    end

    def for_root(root_recording_id, at: Time.current)
      subject = AcquisitionSubject.for_root(root_recording_id)
      return Result.new("unresolved", nil, []) if subject.nil?

      Result.new("resolved", subject, usable_for(subject, root_recording_id, at))
    end

    def delete_for_user!(user_id)
      visitor_ids = IdentityLink.where(user_id: user_id).pluck(:visitor_id)
      IdentityLink.where(user_id: user_id).delete_all
      ConsentLedger.detach_user!(user_id)
      exclusive = visitor_ids.reject { |visitor_id| IdentityLink.exists?(visitor_id: visitor_id) }
      return if exclusive.empty?

      AttributionObservation.where(visitor_id: exclusive).delete_all
      ConsentRecord.where(visitor_id: exclusive, user_id: nil).delete_all
    end

    def delete_for_root!(root_recording_id)
      AttributionObservation.where(root_recording_id: root_recording_id).delete_all
    end

    def record_browser(visitor_id, payload, request, context)
      items = payload["fields"]
      return 0 unless items.is_a?(Array)

      items.count { |item| store_browser(visitor_id, item, request, context) }
    end

    def store_browser(visitor_id, item, request, context)
      return false unless item.is_a?(Hash)

      item = item.stringify_keys
      entry = CollectionCatalog.find(item["provider"], item["name"])
      return false if entry.nil?
      return false unless CollectionCatalog::BROWSER_SOURCES.include?(entry.field.source)

      value = AttributionValues.browser_value(entry.field, item)
      insert(entry, visitor_id, value, request, context)
    end

    def record_server(visitor_id, request, context)
      CollectionCatalog.server_fields.count do |entry|
        value = AttributionValues.server_value(entry.field, request, context)
        insert(entry, visitor_id, value, request, context)
      end
    end

    def insert(entry, visitor_id, value, request, context)
      return if value.blank?
      return unless ConsentLedger.granted?(visitor_id: visitor_id, category: entry.field.consent_category)

      captured_at = Time.current
      AttributionObservation.create!(row(Capture.new(entry, visitor_id, value, request, context, captured_at)))
    end

    def row(capture)
      placement(capture).merge(field_columns(capture))
    end

    def placement(capture)
      {
        visitor_id: capture.visitor_id,
        root_recording_id: capture.context[:root_recording_id],
        session_id: session_digest(capture.request)
      }
    end

    def field_columns(capture)
      field = capture.entry.field
      {
        provider: capture.entry.adapter.key.to_s, field_name: field.name.to_s,
        value: capture.value, source: field.source.to_s, captured_at: capture.captured_at,
        expires_at: expiry(field, capture.captured_at),
        consent_category: field.consent_category.to_s
      }
    end

    def expiry(field, captured_at)
      return if field.retention.nil?

      captured_at + field.retention
    end

    def session_digest(request)
      return if request.nil? || !request.respond_to?(:session)

      identifier = request.session.id
      return if identifier.blank?

      Digest::SHA256.hexdigest(identifier.to_s)
    rescue TypeError, ArgumentError, ActionDispatch::Request::Session::DisabledSessionError
      nil
    end

    def usable_for(subject, root_recording_id, at)
      visitor_ids = IdentityLink.where(user_id: subject.subject_id, confirmed: true).pluck(:visitor_id)
      return [] if visitor_ids.empty?

      AttributionObservation.where(visitor_id: visitor_ids)
                            .where(root_recording_id: [nil, root_recording_id])
                            .where("expires_at IS NULL OR expires_at > ?", at)
                            .order(:captured_at)
                            .select do |row|
        ConsentLedger.granted?(visitor_id: row.visitor_id, category: row.consent_category, at: at)
      end
    end
  end
end
