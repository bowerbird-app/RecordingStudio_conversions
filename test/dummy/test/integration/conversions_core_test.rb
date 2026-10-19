# frozen_string_literal: true

require "test_helper"

class ConversionsCoreTest < ActiveSupport::TestCase
  setup do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudio::RootSwitchable::Current.device_key = "device-from-root-switchable"
  end

  teardown do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudio::RootSwitchable::Current.reset
  end

  test "a confirmed registration becomes one durable occurrence and a repeat does not" do
    user = create_user(confirmed_at: Time.current)
    rule :registration, "users.registered"

    occurrence = publish_registration(user)
    again = publish_registration(user)

    assert_equal occurrence.id, again.id
    assert_equal "matched", occurrence.outcome
    assert_equal user.id, occurrence.actor_id
    assert_equal user.id, occurrence.source_event_id
    assert_equal "device-from-root-switchable", occurrence.visitor_id
    assert_equal user.confirmed_at.to_i, occurrence.confirmed_at.to_i
    refute occurrence.properties.key?("email")
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "registration").count
  end

  test "an unconfirmed user is stored as suppressed and a rolled back event writes nothing" do
    user = create_user(confirmed_at: nil)
    rule :registration, "users.registered"

    occurrence = publish_registration(user)

    assert_equal "suppressed", occurrence.outcome
    assert_equal "unconfirmed_user", occurrence.suppression_reason

    assert_no_difference -> { RecordingStudioConversions::Occurrence.count } do
      ActiveRecord::Base.transaction do
        publish_registration(create_user(confirmed_at: Time.current))
        raise ActiveRecord::Rollback
      end
    end
  end

  test "the host records one acquisition user per root and a trial resolves that user" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    other = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: other.id)

    assert_equal 1, RecordingStudioConversions::AcquisitionSubject.where(root_recording_id: root.id).count
    assert_equal other.id, RecordingStudioConversions::AcquisitionSubject.for_root(root.id).subject_id
    assert_equal root.id, RecordingStudioConversions::AcquisitionSubject.for_root(root.id).root_recording_id

    rule :trial, "stripe.trial_started", first_occurrence: true
    subscription_id = SecureRandom.uuid
    occurrence = publish(
      "trial_started.recording_studio_stripe",
      event_id: "evt_trial_once",
      root_recording_id: root.id,
      subscription_id: subscription_id
    )

    assert_equal "matched", occurrence.outcome
    assert_equal other.id, occurrence.attribution_subject_id
    assert_equal subscription_id, occurrence.subject_id
    assert occurrence.first_occurrence
  end

  test "a trial without an acquisition user is unresolved and a second one is already recorded" do
    root = create_root
    rule :trial, "stripe.trial_started", first_occurrence: true

    missing = publish(
      "trial_started.recording_studio_stripe",
      event_id: "evt_missing",
      root_recording_id: root.id,
      subscription_id: SecureRandom.uuid
    )
    assert_equal "unresolved_acquisition_subject", missing.suppression_reason

    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    publish(
      "trial_started.recording_studio_stripe",
      event_id: "evt_first",
      root_recording_id: root.id,
      subscription_id: SecureRandom.uuid
    )
    second = publish(
      "trial_started.recording_studio_stripe",
      event_id: "evt_second",
      root_recording_id: root.id,
      subscription_id: SecureRandom.uuid
    )

    assert_equal "already_recorded", second.suppression_reason
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "trial", outcome: "matched").count
  end

  test "invoice amount is stored and a trial fee or repeat payment does not match" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    RecordingStudioConversions.configuration.conversion :purchase do
      source "stripe.invoice_paid"
      condition :first_payment, equals: true
      condition :trial_fee, equals: false
    end

    paid = publish(
      "invoice_paid.recording_studio_stripe",
      event_id: "evt_paid",
      root_recording_id: root.id,
      subscription_id: SecureRandom.uuid,
      amount: 4900,
      currency: "usd",
      first_payment: true,
      trial_fee: false
    )
    publish(
      "invoice_paid.recording_studio_stripe",
      event_id: "evt_fee",
      root_recording_id: root.id,
      amount: 100,
      first_payment: true,
      trial_fee: true
    )

    assert_equal "matched", paid.outcome
    assert_equal 4900, paid.properties["amount"]
    assert_equal "usd", paid.properties["currency"]
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "purchase").count
  end

  test "a views event is matched from the views name and core history is ignored" do
    root = create_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: Page.new(title: "Pricing #{SecureRandom.hex(4)}"),
      root_recording: root,
      parent_recording: root
    ).recording
    RecordingStudioConversions.configuration.conversion :pricing_view do
      source "views.recorded"
      recording page.id
    end

    occurrence = publish(
      "recorded.recording_studio_views",
      event_id: SecureRandom.uuid,
      recording_id: page.id,
      recordable_type: "Page",
      recordable_id: page.recordable_id,
      path: "/pricing"
    )
    before = RecordingStudioConversions::Occurrence.count
    ActiveSupport::Notifications.instrument("recordings.event_created", event_id: SecureRandom.uuid, action: "created")

    assert_equal "matched", occurrence.outcome
    assert_equal page.id, occurrence.recording_id
    assert_equal page.recordable_id, occurrence.recordable_id
    assert_equal "Page", occurrence.recordable_type
    assert_nil occurrence.root_recording_id
    assert_equal before, RecordingStudioConversions::Occurrence.count
  end

  private

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
      confirmed_at: confirmed_at
    )
  end

  def create_root
    RecordingStudio.root_recording_for(Workspace.create!(name: "Workspace #{SecureRandom.hex(4)}"))
  end

  def publish_registration(user)
    publish(
      "registration.completed.recording_studio_user",
      user_id: user.id,
      method: :password,
      email: user.email
    )
  end

  def publish(name, payload)
    ActiveSupport::Notifications.instrument(name, payload)
    RecordingStudioConversions::Occurrence.order(:created_at).last
  end
end
