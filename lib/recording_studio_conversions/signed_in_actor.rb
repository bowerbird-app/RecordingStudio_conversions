# frozen_string_literal: true

module RecordingStudioConversions
  # The signed-in user is the host actor. Recording Studio's configuration.actor
  # defaults to Current.actor, which the host sets from its own auth. This gem
  # does not read Warden.
  module SignedInActor
    module_function

    def resolve
      configured_actor || current_actor
    end

    def configured_actor
      return unless defined?(::RecordingStudio)

      value = ::RecordingStudio.configuration.actor
      value = value.call if value.respond_to?(:call)
      actor(value)
    rescue StandardError
      nil
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
