# frozen_string_literal: true

module RecordingStudioConversions
  # The signed-in user is the host actor. Recording Studio's configuration.actor
  # defaults to Current.actor, which the host sets from its own auth. This gem
  # does not read Warden.
  module SignedInActor
    module_function

    def resolve(controller = nil)
      configured_actor(controller) || current_actor
    end

    def configured_actor(controller)
      return unless defined?(::RecordingStudio)

      value = ::RecordingStudio.configuration.actor
      value = invoke(value, controller) if value.respond_to?(:call)
      actor(value)
    rescue StandardError => e
      log_resolver_error(e)
      nil
    end

    # Views calls its resolver with the controller. A stock Recording Studio
    # actor lambda takes no arguments and only reads Current.actor, which an
    # engine request never sets. Pass the controller when the lambda accepts
    # it, and keep a zero-arity lambda working.
    def invoke(resolver, controller)
      return resolver.call if resolver.arity.zero?

      resolver.call(controller)
    end

    def log_resolver_error(exception)
      return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

      ::Rails.logger.error(
        "[RecordingStudioConversions] actor resolver failed: #{exception.class}: #{exception.message}"
      )
    end

    def current_actor
      return unless defined?(::Current) && ::Current.respond_to?(:actor)

      actor(::Current.actor)
    end

    def actor(value)
      value if value.respond_to?(:id)
    end
  end
end
