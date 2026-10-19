# frozen_string_literal: true

module RecordingStudioConversions
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioConversions

    class << self
      def load_yaml_config(app)
        return unless app.respond_to?(:config_for)

        yaml = app.config_for(:recording_studio_conversions)
        RecordingStudioConversions.configuration.merge!(yaml) if yaml.respond_to?(:each)
      rescue StandardError
        nil
      end

      def apply_model_extensions(target)
        apply_extensions(target, extensions_for(:model, extension_keys_for(target)))
      end

      def apply_controller_extensions(target)
        apply_extensions(target, extensions_for(:controller, extension_keys_for(target)))
      end

      private

      def extensions_for(kind, names)
        hooks = RecordingStudioConversions.configuration.hooks
        Array(names).flat_map do |name|
          if kind == :model
            hooks.model_extensions_for(name)
          else
            hooks.controller_extensions_for(name)
          end
        end
      end

      def apply_extensions(target, extensions)
        return unless target

        applied = target.instance_variable_get(:@recording_studio_conversions_applied_extensions) || identity_hash

        extensions.flatten.compact.each do |extension|
          next if applied[extension]

          target.class_eval(&extension)
          applied[extension] = true
        end

        target.instance_variable_set(:@recording_studio_conversions_applied_extensions, applied)
      end

      def extension_keys_for(target)
        names = [target.name, target.name&.demodulize].compact.uniq
        names.map(&:to_sym)
      end

      def identity_hash
        {}.compare_by_identity
      end
    end

    initializer "recording_studio_conversions.subscribe" do
      config.to_prepare { RecordingStudioConversions.install! }
    end

    initializer "recording_studio_conversions.confirmable" do
      config.after_initialize { RecordingStudioConversions::UserConfirmation.assert_confirmable! }
    end

    initializer "recording_studio_conversions.check_contracts" do
      config.after_initialize { RecordingStudioConversions.check! }
    end

    # Run before_initialize hooks
    initializer "recording_studio_conversions.before_initialize",
                before: "recording_studio_conversions.load_config" do |_app|
      RecordingStudioConversions.configuration.hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_conversions.load_config" do |app|
      RecordingStudioConversions::Engine.load_yaml_config(app)

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_conversions)
        xcfg = app.config.x.recording_studio_conversions
        if xcfg.respond_to?(:to_h)
          RecordingStudioConversions.configuration.merge!(xcfg.to_h)
        else
          begin
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudioConversions.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      configuration = RecordingStudioConversions.configuration
      configuration.hooks.run(:on_configuration, configuration)
    end

    # Run after_initialize hooks
    initializer "recording_studio_conversions.after_initialize",
                after: "recording_studio_conversions.load_config" do |_app|
      RecordingStudioConversions.configuration.hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "recording_studio_conversions.apply_model_extensions" do
      config.to_prepare do
        next unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.descendants.each do |model|
          next if model.abstract_class?

          RecordingStudioConversions::Engine.apply_model_extensions(model)
        end
      end
    end

    # Apply controller extensions
    initializer "recording_studio_conversions.apply_controller_extensions" do
      config.to_prepare do
        next unless defined?(ActionController::Base)

        ActionController::Base.descendants.each do |controller|
          RecordingStudioConversions::Engine.apply_controller_extensions(controller)
        end
      end
    end
  end
end
