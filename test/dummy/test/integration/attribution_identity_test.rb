# frozen_string_literal: true

require "test_helper"
require_relative "../support/catalog_ads_adapter"

class AttributionIdentityTest < ActiveSupport::TestCase
  setup do
    RecordingStudioConversions.configuration.clear_adapters!
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = true
    RecordingStudioConversions.configuration.attribution_subject_resolver = nil
    RecordingStudioConversions.configuration.collection_context = nil
    RecordingStudioConversions.configuration.collection_resolvers.clear
    RecordingStudioConversions.configuration.register_adapter :catalog, CatalogAdsAdapter
    RecordingStudioConversions.configuration.destination :catalog, adapter: :catalog, access_token: "secret-token"
    RecordingStudio::RootSwitchable::Current.device_key = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  end

  teardown do
    RecordingStudioConversions.configuration.clear_adapters!
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = false
    RecordingStudioConversions.configuration.attribution_subject_resolver = nil
    RecordingStudioConversions.configuration.collection_context = nil
    RecordingStudioConversions.configuration.collection_resolvers.clear
    RecordingStudio::RootSwitchable::Current.reset
  end

  test "anonymous collection keeps every click and ignores a client visitor id" do
    grant_consent
    record_click("first-click")
    record_click("second-click")

    rows = RecordingStudioConversions::AttributionObservation.order(:captured_at)

    assert_equal %w[first-click second-click], rows.map(&:value)
    assert_equal ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"], rows.map(&:visitor_id).uniq
    assert_equal "catalog", rows.first.provider
    assert_equal 0, RecordingStudioConversions::Occurrence.count
  end

  test "a confirmed registration links the device key and a second user does not replace it" do
    user = create_user(confirmed_at: Time.current)
    other = create_user(confirmed_at: Time.current)
    rule :registration, "users.registered"

    publish_registration(user)
    first = RecordingStudioConversions::IdentityLink.find_by!(user_id: user.id)
    publish_registration(user)
    RecordingStudio::RootSwitchable::Current.device_key = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    publish_registration(other)

    assert_equal first.id, RecordingStudioConversions::IdentityLink.find_by!(user_id: user.id).id
    assert_equal "password", first.method
    assert first.confirmed
    assert_equal 2, RecordingStudioConversions::IdentityLink.where(visitor_id: first.visitor_id).count
  end

  test "an unconfirmed registration does not link until the user is confirmed" do
    user = create_user(confirmed_at: nil)
    rule :registration, "users.registered"
    publish_registration(user)

    assert_equal 0, RecordingStudioConversions::IdentityLink.count

    user.update!(confirmed_at: Time.current)
    RecordingStudioConversions.reevaluate!

    assert RecordingStudioConversions::IdentityLink.exists?(user_id: user.id, confirmed: true)
  end

  test "the host policy attributes a multi-user workspace to the recorded user" do
    root = create_root
    owner = create_user(confirmed_at: Time.current)
    billing = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: owner.id)
    rule :trial, "stripe.trial_started", first_occurrence: true

    occurrence, = publish("trial_started.recording_studio_stripe", trial_payload(root).merge(actor_id: billing.id))

    assert_equal "matched", occurrence.outcome
    assert_equal owner.id, occurrence.attribution_subject_id
    refute_equal billing.id, occurrence.attribution_subject_id
  end

  test "a resolver that names another member is ambiguous and is not substituted" do
    root = create_root
    owner = create_user(confirmed_at: Time.current)
    billing = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: owner.id)
    RecordingStudioConversions.configuration.attribution_subject_resolver = ->(_event) { billing.id }
    rule :trial, "stripe.trial_started", first_occurrence: true
    notices = []
    token = ActiveSupport::Notifications.subscribe("attribution_subject.recording_studio_conversions") do |*args|
      notices << args.last
    end

    occurrence, = publish("trial_started.recording_studio_stripe", trial_payload(root))

    assert_equal "suppressed", occurrence.outcome
    assert_equal "ambiguous_acquisition_subject", occurrence.suppression_reason
    assert_nil occurrence.attribution_subject_id
    assert_equal "ambiguous_acquisition_subject", notices.last[:status]
  ensure
    ActiveSupport::Notifications.unsubscribe(token) if token
  end

  test "a missing acquisition user stays unresolved and does not borrow another root" do
    root = create_root
    other = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: other.id, user_id: user.id)
    rule :trial, "stripe.trial_started", first_occurrence: true

    occurrence, = publish("trial_started.recording_studio_stripe", trial_payload(root))

    assert_equal "unresolved_acquisition_subject", occurrence.suppression_reason
    assert_nil occurrence.attribution_subject_id
  end

  test "a later invoice resolves historical clicks and drops them after expiry or withdrawal" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    grant_consent
    record_click("click-before-signup")
    rule :registration, "users.registered"
    publish_registration(user)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    rule :purchase, "stripe.invoice_paid"
    publish("invoice_paid.recording_studio_stripe", invoice_payload(root))

    found = RecordingStudioConversions.attribution_for(root_recording_id: root.id)

    assert_equal "resolved", found.status
    assert_equal user.id, found.subject.subject_id
    assert_equal ["click-before-signup"], found.observations.map(&:value)

    RecordingStudioConversions::AttributionObservation.update_all(expires_at: 1.minute.ago)
    expired = RecordingStudioConversions.attribution_for(root_recording_id: root.id)
    assert_empty expired.observations
    assert_equal 1, RecordingStudioConversions::AttributionObservation.count

    RecordingStudioConversions::AttributionObservation.update_all(expires_at: 30.days.from_now)
    RecordingStudioConversions.record_consent!(
      visitor_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      category: "advertising",
      granted: false,
      provenance: { "source" => "host" }
    )
    withdrawn = RecordingStudioConversions.attribution_for(root_recording_id: root.id)
    assert_empty withdrawn.observations
    assert_equal 1, RecordingStudioConversions::AttributionObservation.count
  end

  test "observations from another root are not reused and deletion removes a user's rows" do
    root = create_root
    foreign = create_root
    user = create_user(confirmed_at: Time.current)
    grant_consent
    record_click("shared-click")
    RecordingStudioConversions::AttributionObservation.create!(
      visitor_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      root_recording_id: foreign.id,
      provider: "catalog",
      field_name: "click_id",
      value: "foreign-click",
      source: "query_parameter",
      captured_at: Time.current,
      consent_category: "advertising",
      consent_granted: true
    )
    rule :registration, "users.registered"
    publish_registration(user)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)

    found = RecordingStudioConversions.attribution_for(root_recording_id: root.id)
    assert_equal ["shared-click"], found.observations.map(&:value)

    RecordingStudioConversions.delete_attribution_for_user!(user.id)
    RecordingStudioConversions.delete_attribution_for_root!(foreign.id)

    assert_equal 0, RecordingStudioConversions::IdentityLink.where(user_id: user.id).count
    assert_equal 0, RecordingStudioConversions::AttributionObservation.count
  end

  private

  def grant_consent
    RecordingStudioConversions.record_consent!(
      visitor_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      category: "advertising",
      granted: true,
      provenance: { "source" => "host", "email" => "hidden@example.com" }
    )
  end

  def record_click(value)
    RecordingStudioConversions::Collector.call(
      request: nil,
      payload: {
        "visitor_id" => "client-supplied",
        "fields" => [{ "provider" => "catalog", "name" => "click_id", "value" => value }],
        "email" => "person@example.com"
      },
      user: nil
    )
  end

  def rule(key, source, first_occurrence: false)
    RecordingStudioConversions.configuration.conversion key do
      source source
      first_occurrence! if first_occurrence
    end
  end

  def create_user(confirmed_at:)
    User.create!(
      email: "person-#{SecureRandom.hex(4)}@example.com",
      password: "Password123",
      password_confirmation: "Password123",
      confirmed_at: confirmed_at
    )
  end

  def create_root
    RecordingStudio.root_recording_for(Workspace.create!(name: "Workspace #{SecureRandom.hex(4)}"))
  end

  def publish_registration(user)
    publish("registration.completed.recording_studio_user", user_id: user.id, method: :password)
  end

  def trial_payload(root)
    {
      schema_version: 1,
      id: SecureRandom.uuid,
      occurred_at: Time.utc(2026, 10, 19, 2, 0, 0),
      subscription_id: SecureRandom.uuid,
      customer_id: SecureRandom.uuid,
      root_recording_id: root.id
    }
  end

  def invoice_payload(root)
    trial_payload(root).merge(amount: 2900, currency: "usd", invoice_id: "in_first", first_payment: true)
  end

  def publish(name, payload)
    before = RecordingStudioConversions::Occurrence.count
    ActiveSupport::Notifications.instrument(name, payload)
    source_id = payload[:id] || payload[:user_id]
    row = RecordingStudioConversions::Occurrence.find_by(source_event_id: source_id.to_s)
    [row, RecordingStudioConversions::Occurrence.count - before]
  end
end
