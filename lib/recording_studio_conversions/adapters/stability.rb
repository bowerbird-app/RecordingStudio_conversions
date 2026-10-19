# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Provider classes must survive a development reload. Registration asks
    # Rails.autoloaders.main whether Zeitwerk will unload the constant.
    # A required file, an autoload-once path, and a gem class are not unloaded.
    # Anonymous classes are rejected here. The registry turns a repeated
    # registration of the same class into a no-op before this runs, and raises
    # "already registered" for a different class on that key.
    module Stability
      module_function

      def assert!(adapter_class, key)
        raise ArgumentError, anonymous_message(key) if adapter_class.name.to_s.empty?
        return unless reloadable?(adapter_class)

        raise ArgumentError, reloadable_message(adapter_class)
      end

      def reloadable?(adapter_class)
        loader = main_autoloader
        return false unless loader

        loader.unloadable_cpath?(adapter_class.name.to_s)
      end

      def main_autoloader
        return unless defined?(Rails)
        return unless Rails.respond_to?(:application)
        return unless Rails.application

        Rails.autoloaders.main
      end

      def anonymous_message(key)
        "adapter #{key} is anonymous; define a named class in lib/ or a gem, not app/"
      end

      def reloadable_message(adapter_class)
        "adapter #{adapter_class.name} is reloadable; define it in lib/ or a gem, not app/"
      end
    end
  end
end
