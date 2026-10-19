# frozen_string_literal: true

class CreateRecordingStudioConversions < ActiveRecord::Migration[8.1]
  def change
    create_occurrences
    create_acquisition_subjects
  end

  private

  def create_occurrences # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :recording_studio_conversions_occurrences, id: :uuid do |table|
      table.string :rule_key, null: false
      table.string :source_event_name, null: false
      table.string :source_event_id, null: false
      table.string :source, null: false
      table.integer :schema_version, null: false, default: 1
      table.datetime :occurred_at, null: false
      table.uuid :root_recording_id
      table.uuid :recording_id
      table.string :recordable_type
      table.uuid :recordable_id
      table.string :subject_type
      table.uuid :subject_id
      table.string :actor_type
      table.uuid :actor_id
      table.string :attribution_subject_type
      table.uuid :attribution_subject_id
      table.string :visitor_id
      table.jsonb :properties, null: false, default: {}
      table.string :outcome, null: false
      table.string :suppression_reason
      table.datetime :confirmed_at
      table.boolean :first_occurrence, null: false, default: false
      table.timestamps
    end

    add_index :recording_studio_conversions_occurrences, %i[rule_key source_event_id],
              unique: true, name: "idx_rs_conversions_occurrences_idempotency"
    add_index :recording_studio_conversions_occurrences,
              %i[rule_key root_recording_id],
              unique: true,
              where: "outcome = 'matched' AND first_occurrence = true AND root_recording_id IS NOT NULL",
              name: "idx_rs_conversions_first_occurrence_root"
    add_index :recording_studio_conversions_occurrences, :root_recording_id,
              name: "idx_rs_conversions_occurrences_root"
  end

  def create_acquisition_subjects
    create_table :recording_studio_conversions_acquisition_subjects, id: :uuid do |table|
      table.uuid :root_recording_id, null: false
      table.string :subject_type, null: false
      table.uuid :subject_id, null: false
      table.datetime :recorded_at, null: false
      table.timestamps
    end

    add_index :recording_studio_conversions_acquisition_subjects, :root_recording_id,
              unique: true, name: "idx_rs_conversions_one_acquisition_user_per_root"
  end
end
