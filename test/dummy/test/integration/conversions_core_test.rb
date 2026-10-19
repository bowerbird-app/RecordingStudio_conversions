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
    refute paid.properties.key?("subscription_status")
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "purchase").count
  end

  test "a paid invoice on a canceled subscription is not a conversion" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    RecordingStudioConversions.configuration.conversion :purchase do
      source "stripe.invoice_paid"
      condition :first_payment, equals: true
    end

    _canceled, canceled_delta = publish(
      "invoice_paid.recording_studio_stripe",
      invoice_payload(root, first_payment: true, billing_reason: "subscription_cycle", subscription_status: "canceled")
    )
    paid, paid_delta = publish(
      "invoice_paid.recording_studio_stripe",
      invoice_payload(root, first_payment: true, billing_reason: "subscription_create", subscription_status: "active")
    )

    assert_equal 0, canceled_delta
    assert_equal 1, paid_delta
    assert_equal "matched", paid.outcome
    assert_equal "subscription_create", paid.properties["billing_reason"]
    assert_equal "active", paid.properties["subscription_status"]
  end

  test "a page view is confirmed for the viewer rather than the acquisition user" do
    root = create_root
    owner = create_user(confirmed_at: Time.current)
    viewer = create_user(confirmed_at: nil)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: owner.id)
    rule :view, "views.recorded"
    payload = page_view_payload(root: root, recording_id: nil).merge(user_id: viewer.id)

    occurrence, delta = publish("page_view.recorded.recording_studio_views", payload)

    assert_equal 1, delta
    assert_equal "suppressed", occurrence.outcome
    assert_equal "unconfirmed_user", occurrence.suppression_reason
    assert_equal viewer.id, occurrence.actor_id
    assert_nil occurrence.attribution_subject_id

    viewer.update!(confirmed_at: Time.current)
    revised = RecordingStudioConversions.reevaluate!.sole

    assert_equal "matched", revised.outcome
    assert_equal viewer.id, revised.actor_id
    assert_nil revised.attribution_subject_id
  end

  test "reevaluate keeps going when one suppressed row raises" do
    first = create_user(confirmed_at: nil)
    second = create_user(confirmed_at: nil)
    rule :registration, "users.registered"
    publish_registration(first)
    publish_registration(second)
    first.update!(confirmed_at: Time.current)
    second.update!(confirmed_at: Time.current)
    original = RecordingStudioConversions::UserConfirmation.method(:lookup)
    failures = []
    token = ActiveSupport::Notifications.subscribe("failed.recording_studio_conversions") do |*args|
      failures << args.last
    end
    RecordingStudioConversions::UserConfirmation.define_singleton_method(:lookup) do |user_id|
      raise "confirmation lookup failed" if user_id == first.id

      original.call(user_id)
    end

    revised = RecordingStudioConversions.reevaluate!

    assert_equal [second.id], revised.map(&:actor_id)
    assert_equal "suppressed", RecordingStudioConversions::Occurrence.find_by(actor_id: first.id).outcome
    assert_equal "matched", RecordingStudioConversions::Occurrence.find_by(actor_id: second.id).outcome
    assert_equal 1, failures.size
  ensure
    if original
      RecordingStudioConversions::UserConfirmation.define_singleton_method(:lookup, original)
    end
    ActiveSupport::Notifications.unsubscribe(token) if token
  end

  test "an idempotency conflict leaves the suppressed winner unchanged" do
    user = create_user(confirmed_at: nil)
    rule :registration, "users.registered"
    occurrence, = publish_registration(user)
    envelope = RecordingStudioConversions::Envelope.from_record(occurrence)
    change = writer_change("registration", envelope, nil, "matched", nil)

    recovered = occurrence_writer.send(:recover, change)

    assert_equal occurrence.id, recovered.id
    assert_equal "suppressed", recovered.outcome
    assert_equal "unconfirmed_user", recovered.suppression_reason
    assert_equal 1, RecordingStudioConversions::Occurrence.where(rule_key: "registration").count
  end

  test "a first-occurrence conflict records already_recorded without relabeling the winner" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    rule :trial, "stripe.trial_started", first_occurrence: true
    winner, = publish("trial_started.recording_studio_stripe", trial_payload(root))
    subscription = RecordingStudioConversions.configuration.subscriptions.find do |item|
      item.canonical_name == "stripe.trial_started"
    end
    envelope = RecordingStudioConversions::Envelope.from(subscription, trial_payload(root))
    subject = RecordingStudioConversions::AcquisitionSubject.for_root(root.id)
    change = writer_change("trial", envelope, subject, "matched", nil)

    recovered = occurrence_writer(user).send(:recover, change)

    assert_equal "matched", winner.reload.outcome
    assert_equal "suppressed", recovered.outcome
    assert_equal "already_recorded", recovered.suppression_reason
    assert_equal envelope.source_event_id, recovered.source_event_id
    refute_equal winner.id, recovered.id
  end

  test "revising a suppressed row into a first-occurrence conflict records already_recorded" do
    root = create_root
    user = create_user(confirmed_at: Time.current)
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
    rule :trial, "stripe.trial_started", first_occurrence: true
    winner, = publish("trial_started.recording_studio_stripe", trial_payload(root))
    suppressed = winner.dup
    suppressed.source_event_id = SecureRandom.uuid
    suppressed.outcome = "suppressed"
    suppressed.suppression_reason = "unconfirmed_user"
    suppressed.first_occurrence = false
    suppressed.save!
    envelope = RecordingStudioConversions::Envelope.from_record(suppressed)
    subject = RecordingStudioConversions::AcquisitionSubject.for_root(root.id)
    change = writer_change("trial", envelope, subject, "matched", nil)

    revised = occurrence_writer(user).save(change)

    assert_equal "matched", winner.reload.outcome
    assert_equal suppressed.id, revised.id
    assert_equal "suppressed", revised.outcome
    assert_equal "already_recorded", revised.suppression_reason
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

  def invoice_payload(root, first_payment:, billing_reason: nil, subscription_status: nil)
    trial_payload(root).merge(
      amount: 2900,
      currency: "usd",
      invoice_id: first_payment ? "in_first" : "in_second",
      first_payment: first_payment,
      billing_reason: billing_reason,
      subscription_status: subscription_status
    ).compact
  end

  def writer_change(rule_key, envelope, subject, outcome, reason)
    rule = RecordingStudioConversions.configuration.rules.find { |item| item.key == rule_key }
    RecordingStudioConversions::OccurrenceWriter::Change.new(rule, envelope, subject, outcome, reason)
  end

  def occurrence_writer(user = nil)
    confirmations = {}
    confirmations[user.id] = [:found, user.confirmed_at] if user
    RecordingStudioConversions::OccurrenceWriter.new(confirmations: confirmations)
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

class ConversionsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = true
  end

  teardown do
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.raise_errors = false
    cleanup_race(@root, @user)
  end

  test "concurrent deliveries of one stripe id leave a single row" do
    workspace = Workspace.create!(name: "Workspace #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(workspace)
    @user = User.create!(
      email: "person-#{SecureRandom.hex(4)}@example.com",
      password: "Password123",
      password_confirmation: "Password123",
      confirmed_at: Time.current
    )
    RecordingStudioConversions.record_acquisition_user!(root_recording_id: @root.id, user_id: @user.id)
    RecordingStudioConversions.configuration.conversion :trial do
      source "stripe.trial_started"
      first_occurrence!
    end
    payload = {
      schema_version: 1,
      id: SecureRandom.uuid,
      occurred_at: Time.utc(2026, 10, 19, 2, 0, 0),
      subscription_id: SecureRandom.uuid,
      customer_id: SecureRandom.uuid,
      root_recording_id: @root.id
    }
    ready = Queue.new
    go = Queue.new
    started = Queue.new
    errors = Queue.new

    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          started << Time.now.to_f
          ActiveSupport::Notifications.instrument("trial_started.recording_studio_stripe", payload)
        end
      rescue StandardError => error
        errors << error
      end
    end
    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    assert_empty errors
    starts = 2.times.map { started.pop }
    assert_in_delta starts[0], starts[1], 1
    assert_equal 1, RecordingStudioConversions::Occurrence.where(source_event_id: payload[:id]).count
  end

  private

  def cleanup_race(root, user)
    return if root.nil?

    connection = ActiveRecord::Base.connection
    recording_ids = connection.select_values(<<~SQL.squish)
      SELECT id FROM recording_studio_recordings
      WHERE id = #{connection.quote(root.id)} OR root_recording_id = #{connection.quote(root.id)}
    SQL
    quoted_ids = recording_ids.map { |id| connection.quote(id) }.join(", ")
    connection.execute("DELETE FROM recording_studio_conversions_occurrences WHERE root_recording_id = #{connection.quote(root.id)}")
    connection.execute("DELETE FROM recording_studio_conversions_acquisition_subjects WHERE root_recording_id = #{connection.quote(root.id)}")
    unless quoted_ids.empty?
      connection.execute("DELETE FROM recording_studio_events WHERE recording_id IN (#{quoted_ids})")
      connection.execute("DELETE FROM recording_studio_recordings WHERE id IN (#{quoted_ids})")
    end
    connection.execute("DELETE FROM workspaces WHERE id = #{connection.quote(root.recordable_id)}")
    connection.execute("DELETE FROM users WHERE id = #{connection.quote(user.id)}") if user
  end
end
