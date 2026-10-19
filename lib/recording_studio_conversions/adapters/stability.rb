# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Provider classes must survive a development reload. Registration asks
    # Rails.autoloaders.main whether Zeitwerk will unload the constant, and
    # skips that question when the loader has no unloadable_cpath?. The check
    # only fires when reloading is on. A gem class, a file required from the
    # initializer before setup, and autoload_lib_once are not unloaded.
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
        return false unless loader.respond_to?(:unloadable_cpath?)

        loader.unloadable_cpath?(adapter_class.name.to_s)
      end

      def main_autoloader
        return unless defined?(Rails)
        return unless Rails.respond_to?(:application)
        return unless Rails.application

        Rails.autoloaders.main
      end

      def anonymous_message(key)
        "adapter #{key} is anonymous; use a gem class, a file required from the initializer, or autoload_lib_once"
      end

      def reloadable_message(adapter_class)
        name = adapter_class.name
        "adapter #{name} is reloadable; use a gem class, a file required from the initializer, or autoload_lib_once"
      end
    end
  end
end
