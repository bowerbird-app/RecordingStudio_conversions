# frozen_string_literal: true

module RecordingStudioConversions
  module Adapters
    # Provider classes must survive a development reload. Named classes in lib/
    # or in a gem do. Anonymous classes and classes Zeitwerk reloads from app/
    # do not. Duplicate registry keys are rejected before this runs.
    module Stability
      module_function

      def assert!(adapter_class, key)
        raise ArgumentError, anonymous_message(key) if adapter_class.name.to_s.empty?
        return unless reloadable?(adapter_class)

        raise ArgumentError, reloadable_message(adapter_class)
      end

      def reloadable?(adapter_class)
        file = source_file(adapter_class)
        return false unless file

        reloadable_directories.any? { |dir| inside?(file, dir) }
      end

      def source_file(adapter_class)
        Object.const_source_location(adapter_class.name)&.first
      end

      def reloadable_directories
        application = defined?(Rails) && Rails.respond_to?(:application) ? Rails.application : nil
        return [] unless application

        Rails.autoloaders.main.dirs
      end

      def inside?(file, dir)
        root = File.expand_path(dir.to_s)
        expanded = File.expand_path(file)
        expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
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
