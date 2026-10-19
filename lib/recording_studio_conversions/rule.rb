# frozen_string_literal: true

module RecordingStudioConversions
  Condition = Data.define(:property, :equals) do
    def match?(properties)
      properties[property] == equals
    end
  end

  class RuleBuilder
    def initialize(key)
      @key = key.to_s
      @conditions = []
      @first_occurrence = false
    end

    def source(name)
      @source = name.to_s
    end

    def condition(property, equals:)
      @conditions << Condition.new(property.to_s, equals)
    end

    def root(recording_id)
      @root_recording_id = recording_id
    end

    def recording(recording_id)
      @recording_id = recording_id
    end

    def first_occurrence!
      @first_occurrence = true
    end

    def to_rule
      raise ArgumentError, "conversion #{@key} needs a source" if @source.blank?

      Rule.new(
        key: @key,
        source: @source,
        conditions: @conditions,
        root_recording_id: @root_recording_id,
        recording_id: @recording_id,
        first_occurrence: @first_occurrence
      )
    end
  end

  Rule = Data.define(:key, :source, :conditions, :root_recording_id, :recording_id, :first_occurrence) do
    def self.build(key, &)
      builder = RuleBuilder.new(key)
      builder.instance_eval(&)
      builder.to_rule
    end

    def matches?(envelope)
      return false unless envelope.name == source
      return false if root_recording_id && envelope.root_recording_id != root_recording_id
      return false if recording_id && envelope.recording_id != recording_id

      conditions.all? { |condition| condition.match?(envelope.properties) }
    end
  end
end
