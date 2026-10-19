# frozen_string_literal: true

require "test_helper"

class ConversionsContractTest < Minitest::Test
  def setup
    @previous = RecordingStudioConversions.instance_variable_get(:@configuration)
    @configuration = RecordingStudioConversions::Configuration.new
    @configuration.user_class_name = "User"
    RecordingStudioConversions.instance_variable_set(:@configuration, @configuration)
  end

  def teardown
    RecordingStudioConversions.instance_variable_set(:@configuration, @previous)
  end

  def test_subscriptions_use_producer_names_and_id_keys
    names = @configuration.subscriptions.to_h { |subscription| [subscription.source_name, subscription] }

    assert_equal :user_id, names.fetch("registration.completed.recording_studio_user").id_key
    assert_equal :id, names.fetch("trial_started.recording_studio_stripe").id_key
    assert_equal :id, names.fetch("invoice_paid.recording_studio_stripe").id_key
    views = names.fetch("page_view.recorded.recording_studio_views")
    assert_equal "views.recorded", views.canonical_name
    assert_equal :page_view_id, views.id_key
    refute names.key?("recorded.recording_studio_views")
    refute names.key?("recordings.event_created")
  end

  def test_invoice_rule_uses_first_payment_and_ignores_a_missing_trial_fee
    @configuration.conversion :purchase do
      source "stripe.invoice_paid"
      condition :first_payment, equals: true
    end
    rule = @configuration.rules.first
    paid = envelope("stripe.invoice_paid", first_payment: true, amount: 2900)
    repeat = envelope("stripe.invoice_paid", first_payment: false, amount: 2900)
    omitted = envelope("stripe.invoice_paid", amount: 2900)

    assert rule.matches?(paid)
    refute rule.matches?(repeat)
    refute rule.matches?(omitted)
    refute paid.properties.key?("trial_fee")
    refute paid.properties.key?("email")
  end

  def test_stripe_source_id_is_the_domain_event_id_and_schema_is_honoured
    subscription = @configuration.subscriptions.find { |item| item.canonical_name == "stripe.trial_started" }
    domain_id = "33333333-3333-4333-8333-333333333333"
    envelope = RecordingStudioConversions::Envelope.from(
      subscription,
      schema_version: 1,
      id: domain_id,
      occurred_at: Time.utc(2026, 10, 19),
      subscription_id: "44444444-4444-4444-8444-444444444444",
      customer_id: "55555555-5555-4555-8555-555555555555",
      root_recording_id: "66666666-6666-4666-8666-666666666666",
      event_id: "evt_ignored",
      email: "person@example.com"
    )

    assert envelope.usable?
    assert_equal domain_id, envelope.source_event_id
    assert_equal 1, envelope.schema_version
    refute envelope.properties.key?("email")
  end

  def test_unknown_schema_and_a_missing_source_id_are_logged_unusable
    subscription = @configuration.subscriptions.find { |item| item.canonical_name == "stripe.invoice_paid" }
    notices = []
    token = ActiveSupport::Notifications.subscribe(RecordingStudioConversions::Configuration::UNUSABLE_EVENT) do |*args|
      notices << args.last
    end
    missing = RecordingStudioConversions::Envelope.from(subscription, schema_version: 1, amount: 1)
    foreign = RecordingStudioConversions::Envelope.from(subscription, schema_version: 2, id: SecureRandom.uuid)

    refute missing.usable?
    refute foreign.usable?
    assert_equal 2, notices.size
    assert_equal 2, notices.last[:schema_version]
  ensure
    ActiveSupport::Notifications.unsubscribe(token) if token
  end

  def test_visitor_id_prefers_the_payload_over_the_device_key
    install_device_key!
    RecordingStudio::RootSwitchable::Current.device_key = "device-from-root-switchable"

    assert_equal "from-payload", RecordingStudioConversions::VisitorId.resolve(visitor_id: "from-payload")
    assert_equal "device-from-root-switchable", RecordingStudioConversions::VisitorId.resolve({})
  ensure
    RecordingStudio::RootSwitchable::Current.reset if defined?(RecordingStudio::RootSwitchable::Current)
  end

  def test_registration_source_id_is_the_user_id
    subscription = @configuration.subscriptions.first
    user_id = "11111111-1111-4111-8111-111111111111"
    envelope = RecordingStudioConversions::Envelope.from(subscription, user_id: user_id, method: :password)

    assert_equal user_id, envelope.source_event_id
    assert_equal "User", envelope.actor_type
    assert_equal "password", envelope.properties["method"].to_s
  end

  private

  def install_device_key!
    return if defined?(RecordingStudio::RootSwitchable::Current)

    root = Module.new
    root.const_set(:Current, Class.new do
      class << self
        attr_accessor :device_key

        def reset
          self.device_key = nil
        end
      end
    end)
    RecordingStudio.const_set(:RootSwitchable, root)
  end

  def envelope(name, **payload)
    subscription = @configuration.subscriptions.find { |item| item.canonical_name == name }
    RecordingStudioConversions::Envelope.from(subscription, payload.merge(id: SecureRandom.uuid, schema_version: 1))
  end
end
