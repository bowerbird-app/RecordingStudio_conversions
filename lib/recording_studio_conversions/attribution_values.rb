# frozen_string_literal: true

module RecordingStudioConversions
  # Turns a declared field into a stored string. Browser payloads are not a source
  # for request, session, resolver, customer, workspace, or event fields.
  module AttributionValues
    REQUEST_READERS = {
      user_agent: :user_agent.to_proc,
      referrer: :referrer.to_proc,
      path: :path.to_proc,
      ip_address: :remote_ip.to_proc
    }.freeze
    VALUE_LIMIT = 512

    module_function

    def browser_value(field, item)
      normalize(field, item["value"])
    end

    def server_value(field, request, context)
      raw = read_server(field, request, context)
      normalize(field, raw)
    end

    def read_server(field, request, context)
      case field.source
      when :request then request_value(field.name, request)
      when :session then session_value(field.name, request)
      when :resolver then resolver_value(field.name, context)
      else context_value(field, context)
      end
    end

    def request_value(name, request)
      reader = REQUEST_READERS[name.to_sym]
      return if reader.nil? || request.nil?

      reader.call(request)
    end

    def session_value(name, request)
      return if request.nil? || !request.respond_to?(:session)

      request.session[name.to_s]
    end

    def resolver_value(name, context)
      resolver = RecordingStudioConversions.configuration.collection_resolvers[name.to_sym]
      return if resolver.nil?

      resolver.call(context)
    end

    def context_value(field, context)
      bucket = context[field.source]
      return if bucket.nil?

      bucket[field.name.to_s] || bucket[field.name.to_sym]
    end

    def normalize(field, raw)
      text = raw.is_a?(String) ? raw.strip : raw.to_s
      return if raw.nil? || text.empty? || text.length > VALUE_LIMIT
      return unless typed?(field, text)

      text
    end

    def typed?(field, text)
      case field.type
      when :integer then text.match?(/\A-?\d+\z/)
      when :boolean then %w[true false].include?(text)
      else !text.match?(/[\u0000-\u001f]/)
      end
    end
  end
end
