# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AttributionInspectorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    configuration = RecordingStudioConversions.configuration
    configuration.clear_adapters!
    configuration.register_adapter :dummy_ads, DummyAdsAdapter
    configuration.destination :dummy_ads, adapter: :dummy_ads
  end

  teardown do
    RecordingStudioConversions.configuration.clear_adapters!
  end

  test "grant revoke acquisition and delete submit through forms" do
    user = confirmed_user
    sign_in user
    Workspace.create!(name: "Inspector buttons #{SecureRandom.hex(4)}")
    get attribution_inspector_path

    assert_response :success
    assert_select %(form[method="post"][action="/attribution/consent"] input[name="granted"][value="true"])
    assert_select %(form[method="post"][action="/attribution/consent"] input[name="category"][value="advertising"])
    assert_select %(form[method="post"][action="/attribution/consent"] button[type="submit"]), text: "Grant advertising"
    assert_select %(form[method="post"][action="/attribution/consent"] input[name="granted"][value="false"])
    assert_select %(form[method="post"][action="/attribution/consent"] button[type="submit"]), text: "Revoke advertising"
    assert_select %(form[method="post"][action="/attribution/acquisition"] button[type="submit"]), text: "Use me as the acquisition user"
    assert_select %(form[method="post"][action^="/attribution/users/"] input[name="_method"][value="delete"])
    assert_select %(form[method="post"][action^="/attribution/users/"] button[type="submit"]), text: "Delete attribution"
  end

  test "the inspector requires a signed-in user and is linked from the nav" do
    get attribution_inspector_path

    assert_redirected_to new_user_session_path

    sign_in confirmed_user
    get root_path

    assert_response :success
    assert_includes response.body, attribution_inspector_path
  end

  test "grant and revoke are listed newest first with the device and user" do
    user = confirmed_user
    sign_in user

    get attribution_inspector_path

    assert_response :success
    assert_includes response.body, "Grant advertising"
    assert_includes response.body, "Revoke advertising"
    assert_includes response.body, "Use Password."
    refute_includes response.body, 'value="Password"'
    assert_includes response.body, user.email
    assert RecordingStudioConversions::IdentityLink.exists?(user_id: user.id)
    assert_equal 0, RecordingStudioConversions::ConsentRecord.where(user_id: user.id).count

    post attribution_consent_path, params: { category: "advertising", granted: "true" }
    assert_redirected_to attribution_inspector_path
    granted = RecordingStudioConversions::ConsentRecord.find_by!(user_id: user.id, granted: true)

    travel 1.second do
      post attribution_consent_path, params: { category: "advertising", granted: "false" }
    end
    follow_redirect!

    withdrawn = RecordingStudioConversions::ConsentRecord.where(user_id: user.id, granted: false).order(recorded_at: :desc).first
    consents_html = response.body.split("Consents", 2).last.split("Observations", 2).first
    assert_operator consents_html.index(withdrawn.recorded_at.utc.iso8601), :<,
                    consents_html.index(granted.recorded_at.utc.iso8601)
    assert_includes response.body, "withdrawn"
    assert_includes response.body, RecordingStudioConversions::IdentityLink.find_by!(user_id: user.id).visitor_id
  end

  test "observations stay on the page and still resolve for the other linked user" do
    first = confirmed_user
    second = confirmed_user
    sign_in first
    get attribution_inspector_path
    visitor_id = RecordingStudioConversions::IdentityLink.find_by!(user_id: first.id).visitor_id
    workspace = Workspace.create!(name: "Inspector #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    RecordingStudioConversions.record_consent!(
      visitor_id: visitor_id, category: "advertising", granted: true, user_id: second.id
    )
    RecordingStudioConversions::AttributionObservation.create!(
      visitor_id: visitor_id, provider: "dummy_ads", field_name: "fbclid", value: "TEST123",
      source: "query_parameter", captured_at: Time.current, consent_category: "advertising"
    )
    RecordingStudioConversions::IdentityLink.insert(
      {
        id: SecureRandom.uuid, visitor_id: visitor_id, user_id: second.id, auth_method: nil,
        linked_at: Time.current, confirmed: true, created_at: Time.current, updated_at: Time.current
      },
      unique_by: :idx_rs_conv_links_pair
    )
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: second.id)

    sign_in second
    delete attribution_user_path(first.id)
    follow_redirect!

    assert_includes response.body, "TEST123"
    assert_includes response.body, "fbclid=TEST123"
    refute RecordingStudioConversions::IdentityLink.exists?(user_id: first.id)
    assert RecordingStudioConversions::IdentityLink.exists?(user_id: second.id)
  end

  test "delete attribution is only offered for the current device" do
    user = confirmed_user
    foreign = confirmed_user
    sign_in user
    get attribution_inspector_path
    visitor_id = RecordingStudioConversions::IdentityLink.find_by!(user_id: user.id).visitor_id
    RecordingStudioConversions::IdentityLink.insert(
      {
        id: SecureRandom.uuid, visitor_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", user_id: foreign.id,
        auth_method: nil, linked_at: Time.current, confirmed: true, created_at: Time.current, updated_at: Time.current
      },
      unique_by: :idx_rs_conv_links_pair
    )

    get attribution_inspector_path

    assert_includes response.body, foreign.email
    assert_equal 1, response.body.scan("Delete attribution").size
    delete attribution_user_path(foreign.id)
    follow_redirect!

    assert_includes response.body, "not linked to this device"
    assert RecordingStudioConversions::IdentityLink.exists?(user_id: foreign.id, visitor_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    assert RecordingStudioConversions::IdentityLink.exists?(user_id: user.id, visitor_id: visitor_id)
  end

  private

  def confirmed_user
    User.create!(
      email: "inspector-#{SecureRandom.hex(4)}@example.com",
      password: "Password123",
      password_confirmation: "Password123",
      confirmed_at: Time.current
    )
  end
end
