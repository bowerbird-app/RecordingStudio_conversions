# frozen_string_literal: true

require "test_helper"

class ConversionsCoreTest < ActiveSupport::TestCase
  setup do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = true
    RecordingStudio::RootSwitchable::Current.device_key = "device-from-root-switchable"
  end

  teardown do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = false
    RecordingStudio::RootSwitchable::Current.reset
  end

  test "a confirmed registration is one occurrence and a repeat does not insert" do
    user = create_user(confirmed_at: Time.current)
    rule :registration, "users.registered"

    occurrence, delta = publish_registration(user)
    again, again_delta = publish_registration(user)

    assert_equal 1, delta
    assert_equal 0, again_delta
    assert_equal occurrence.id, again.id
    assert_equal "matched", occurrence.outcome
    assert_equal user.id, occurrence.actor_id
    assert_equal user.id, occurrence.source_event_id
    assert_equal "device-from-root-switchable", occurrence.visitor_id
    assert_equal user.confirmed_at.to_i, occurrence.confirmed_at.to_i
    refute occurrence.properties.key?("email")
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "registration").count
  end

  test "an unconfirmed user is suppressed and a later confirmation can be reevaluated" do
    user = create_user(confirmed_at: nil)
    rule :registration, "users.registered"

    occurrence, delta = publish_registration(user)

    assert_equal 1, delta
    assert_equal "suppressed", occurrence.outcome
    assert_equal "unconfirmed_user", occurrence.suppression_reason

    user.update!(confirmed_at: Time.current)
    revised = RecordingStudioConversions.reevaluate!(rule_key: "registration").sole

    assert_equal occurrence.id, revised.id
    assert_equal "matched", revised.outcome
    assert_nil revised.suppression_reason
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "registration").count
  end

  test "a matcher error is isolated unless raise_errors is set" do
    user = create_user(confirmed_at: Time.current)
    rule :registration, "users.registered"
    RecordingStudioConversions.configuration.raise_errors = false
    failures = []
    token = ActiveSupport::Notifications.subscribe("failed.recording_studio_conversions") do |*args|
      failures << args.last
    end
    original = RecordingStudioConversions::UserConfirmation.method(:lookup)
    RecordingStudioConversions::UserConfirmation.define_singleton_method(:lookup) { |*| raise "confirmation lookup failed" }

    assert_nothing_raised { publish_registration(user) }
    assert_equal 1, failures.size
    assert_equal 0, RecordingStudioConversions::Occurrence.count
    assert User.exists?(user.id)

    RecordingStudioConversions.configuration.raise_errors = true
    assert_raises(RuntimeError) { publish_registration(user) }
  ensure
    if original
      RecordingStudioConversions::UserConfirmation.define_singleton_method(:lookup, original)
    end
    ActiveSupport::Notifications.unsubscribe(token) if token
  end

  test "the host records one acquisition user per root and a replay promotes a trial" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    other = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: other.id)

    assert_equal 1, RecordingStudioConversions::AcquisitionSubject.where(root_recording_id: root.id).count
    subject = RecordingStudioConversions::AcquisitionSubject.for_root(root.id)
    assert_equal other.id, subject.subject_id
    assert_equal "User", subject.subject_type

    rule :trial, "stripe.trial_started", first_occurrence: true
    payload = trial_payload(root)
    occurrence, delta = publish("trial_started.recording_studio_stripe", payload)
    again, again_delta = publish("trial_started.recording_studio_stripe", payload)

    assert_equal 1, delta
    assert_equal 0, again_delta
    assert_equal occurrence.id, again.id
    assert_equal "matched", occurrence.reload.outcome
    assert_equal other.id, occurrence.attribution_subject_id
    assert_equal payload[:subscription_id], occurrence.subject_id
    assert_equal payload[:id], occurrence.source_event_id
    assert occurrence.first_occurrence
    refute occurrence.properties.key?("customer_id")
  end

  test "a trial before the acquisition user is unresolved until reevaluate, and a second trial does not match" do
    root = create_root
    rule :trial, "stripe.trial_started", first_occurrence: true
    first = trial_payload(root)

    missing, = publish("trial_started.recording_studio_stripe", first)
    assert_equal "unresolved_acquisition_subject", missing.suppression_reason
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "trial").count

    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    revised = RecordingStudioConversions.reevaluate!.sole
    assert_equal "matched", revised.outcome
    assert_equal user.id, revised.attribution_subject_id

    replacement = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: replacement.id)
    second, second_delta = publish("trial_started.recording_studio_stripe", trial_payload(root))

    assert_equal 1, second_delta
    assert_equal "already_recorded", second.suppression_reason
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "trial", outcome: "matched").count
    assert_equal replacement.id, RecordingStudioConversions::AcquisitionSubject.for_root(root.id).subject_id
  end

  test "concurrent deliveries of one stripe id leave a single row" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    rule :trial, "stripe.trial_started", first_occurrence: true
    payload = trial_payload(root)
    errors = Queue.new

    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          publish("trial_started.recording_studio_stripe", payload)
        end
      rescue StandardError => error
        errors << error
      end
    end
    threads.each(&:join)

    assert_empty errors
    assert_equal 1, RecordingStudioConversions::Occurrence.where(source_event_id: payload[:id]).count
  end

  test "invoice amount is stored and a later invoice is not the first payment" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    RecordingStudioConversions.configuration.conversion :purchase do
      source "stripe.invoice_paid"
      condition :first_payment, equals: true
    end

    paid, paid_delta = publish("invoice_paid.recording_studio_stripe", invoice_payload(root, first_payment: true))
    _repeat, repeat_delta = publish("invoice_paid.recording_studio_stripe", invoice_payload(root, first_payment: false))

    assert_equal 1, paid_delta
    assert_equal 0, repeat_delta
    assert_equal "matched", paid.outcome
    assert_equal 2900, paid.properties["amount"]
    assert_equal "usd", paid.properties["currency"]
    assert_equal true, paid.properties["first_payment"]
    assert_equal "in_first", paid.properties["invoice_id"]
    refute paid.properties.key?("trial_fee")
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "purchase").count
  end

  test "an anonymous page view keeps the payload visitor and recording" do
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
    payload = page_view_payload(root: root, recording_id: page.id)

    occurrence, delta = publish("page_view.recorded.recording_studio_views", payload)
    _ignored, ignored_delta = publish("recordings.event_created", event_id: SecureRandom.uuid, action: "created")

    assert_equal 1, delta
    assert_equal 0, ignored_delta
    assert_equal "matched", occurrence.outcome
    assert_equal page.id, occurrence.recording_id
    assert_equal payload[:page_view_id], occurrence.source_event_id
    assert_equal "from-payload", occurrence.visitor_id
    assert_equal "/pricing", occurrence.properties["path"]
    assert_equal({ "utm_source" => "newsletter", "gclid" => "click-1" }, occurrence.properties["query_params"])
    assert_nil occurrence.actor_id
    assert_equal 1, RecordingStudioConversions::Occurrence.count
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
      password_confirmation: "Password123",
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
      method: :password
    )
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

  def invoice_payload(root, first_payment:)
    trial_payload(root).merge(
      amount: 2900,
      currency: "usd",
      invoice_id: first_payment ? "in_first" : "in_second",
      first_payment: first_payment
    )
  end

  def page_view_payload(root:, recording_id:)
    {
      schema_version: 1,
      occurred_at: Time.utc(2026, 10, 19, 2, 3, 4).iso8601,
      path: "/pricing",
      root_recording_id: root.id,
      user_id: nil,
      visitor_id: "from-payload",
      referrer: "https://press.example/from",
      query_params: { "utm_source" => "newsletter", "gclid" => "click-1" },
      page_view_id: SecureRandom.uuid,
      recording_id: recording_id
    }
  end

  def publish(name, payload)
    before = RecordingStudioConversions::Occurrence.count
    ActiveSupport::Notifications.instrument(name, payload)
    source_id = payload[:id] || payload[:page_view_id] || payload[:user_id]
    row = RecordingStudioConversions::Occurrence.find_by(source_event_id: source_id.to_s) if source_id
    [row, RecordingStudioConversions::Occurrence.count - before]
  end
end
