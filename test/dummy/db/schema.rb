# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "recording_studio_access_constraints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "allowed_audiences", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_constraints_on_action"
  end

  create_table "recording_studio_access_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", limit: 64, null: false
    t.string "manager_actor_type", null: false
    t.uuid "manager_actor_id", null: false
    t.string "accepted_by_actor_type"
    t.uuid "accepted_by_actor_id"
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "email"], name: "idx_rs_access_invitations_one_active", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["recording_id"], name: "index_recording_studio_access_invitations_on_recording_id"
    t.index ["token_digest"], name: "idx_rs_access_invitations_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "access_invitations_not_accepted_and_revoked"
  end

  create_table "recording_studio_access_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_rules_on_action"
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.string "role", default: "view", null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_conversions_acquisition_subjects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "root_recording_id", null: false
    t.string "subject_type", null: false
    t.uuid "subject_id", null: false
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_recording_id"], name: "idx_rs_conversions_one_acquisition_user_per_root", unique: true
  end

  create_table "recording_studio_conversions_attribution_observations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "visitor_id", null: false
    t.uuid "root_recording_id"
    t.string "session_id"
    t.string "provider", null: false
    t.string "field_name", null: false
    t.text "value", null: false
    t.string "source", null: false
    t.datetime "captured_at", null: false
    t.datetime "expires_at"
    t.string "consent_category", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "idx_rs_conv_obs_expires"
    t.index ["root_recording_id"], name: "idx_rs_conv_obs_root"
    t.index ["visitor_id", "captured_at"], name: "idx_rs_conv_obs_visitor_time"
    t.index ["visitor_id", "provider", "field_name", "captured_at"], name: "idx_rs_conv_obs_visitor_field"
  end

  create_table "recording_studio_conversions_consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "visitor_id", null: false
    t.uuid "user_id"
    t.string "category", null: false
    t.boolean "granted", default: false, null: false
    t.datetime "recorded_at", null: false
    t.datetime "withdrawn_at"
    t.jsonb "provenance", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "idx_rs_conv_consents_user"
    t.index ["visitor_id", "category", "recorded_at"], name: "idx_rs_conv_consents_lookup"
  end

  create_table "recording_studio_conversions_identity_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "visitor_id", null: false
    t.uuid "user_id", null: false
    t.string "auth_method"
    t.datetime "linked_at", null: false
    t.boolean "confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "idx_rs_conv_links_user"
    t.index ["visitor_id", "user_id"], name: "idx_rs_conv_links_pair", unique: true
  end

  create_table "recording_studio_conversions_occurrences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "rule_key", null: false
    t.string "source_event_name", null: false
    t.string "source_event_id", null: false
    t.string "source", null: false
    t.integer "schema_version", default: 1, null: false
    t.datetime "occurred_at", null: false
    t.uuid "root_recording_id"
    t.uuid "recording_id"
    t.string "recordable_type"
    t.uuid "recordable_id"
    t.string "subject_type"
    t.uuid "subject_id"
    t.string "actor_type"
    t.uuid "actor_id"
    t.string "attribution_subject_type"
    t.uuid "attribution_subject_id"
    t.string "visitor_id"
    t.jsonb "properties", default: {}, null: false
    t.string "outcome", null: false
    t.string "suppression_reason"
    t.datetime "confirmed_at"
    t.boolean "first_occurrence", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_recording_id"], name: "idx_rs_conversions_occurrences_root"
    t.index ["rule_key", "root_recording_id"], name: "idx_rs_conversions_first_occurrence_root", unique: true, where: "(((outcome)::text = 'matched'::text) AND (first_occurrence = true) AND (root_recording_id IS NOT NULL))"
    t.index ["rule_key", "source_event_id"], name: "idx_rs_conversions_occurrences_idempotency", unique: true
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
end
