# frozen_string_literal: true

class CreateRecordingStudioConversionsAttribution < ActiveRecord::Migration[8.1]
  def change
    create_observations
    create_identity_links
    create_consents
  end

  private

  def create_observations # rubocop:disable Metrics/MethodLength
    create_table :recording_studio_conversions_attribution_observations, id: :uuid do |table|
      table.string :visitor_id, null: false
      table.uuid :root_recording_id
      table.string :session_id
      table.string :provider, null: false
      table.string :field_name, null: false
      table.text :value, null: false
      table.string :source, null: false
      table.datetime :captured_at, null: false
      table.datetime :expires_at
      table.string :consent_category, null: false
      table.timestamps
    end

    add_index :recording_studio_conversions_attribution_observations,
              %i[visitor_id captured_at],
              name: "idx_rs_conv_obs_visitor_time"
    add_index :recording_studio_conversions_attribution_observations,
              %i[visitor_id provider field_name captured_at],
              name: "idx_rs_conv_obs_visitor_field"
    add_index :recording_studio_conversions_attribution_observations,
              :expires_at,
              name: "idx_rs_conv_obs_expires"
    add_index :recording_studio_conversions_attribution_observations,
              :root_recording_id,
              name: "idx_rs_conv_obs_root"
  end

  def create_identity_links # rubocop:disable Metrics/MethodLength
    create_table :recording_studio_conversions_identity_links, id: :uuid do |table|
      table.string :visitor_id, null: false
      table.uuid :user_id, null: false
      table.string :auth_method
      table.datetime :linked_at, null: false
      table.boolean :confirmed, null: false, default: false
      table.timestamps
    end

    add_index :recording_studio_conversions_identity_links,
              %i[visitor_id user_id],
              unique: true,
              name: "idx_rs_conv_links_pair"
    add_index :recording_studio_conversions_identity_links,
              :user_id,
              name: "idx_rs_conv_links_user"
  end

  def create_consents # rubocop:disable Metrics/MethodLength
    create_table :recording_studio_conversions_consents, id: :uuid do |table|
      table.string :visitor_id, null: false
      table.uuid :user_id
      table.string :category, null: false
      table.boolean :granted, null: false, default: false
      table.datetime :recorded_at, null: false
      table.datetime :withdrawn_at
      table.jsonb :provenance, null: false, default: {}
      table.timestamps
    end

    add_index :recording_studio_conversions_consents,
              %i[visitor_id category recorded_at],
              name: "idx_rs_conv_consents_lookup"
    add_index :recording_studio_conversions_consents,
              :user_id,
              name: "idx_rs_conv_consents_user"
  end
end
