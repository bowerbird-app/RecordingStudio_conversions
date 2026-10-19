# frozen_string_literal: true

require "test_helper"

class RecordingStudioConversionsTest < Minitest::Test
  def setup
    @configuration = RecordingStudioConversions::Configuration.new
  end

  def test_default_subscriptions_use_provider_neutral_names
    names = @configuration.subscriptions.to_h { |subscription| [subscription.source_name, subscription.canonical_name] }

    assert_equal "users.registered", names.fetch("registration.completed.recording_studio_user")
    assert_equal "stripe.trial_started", names.fetch("trial_started.recording_studio_stripe")
    assert_equal "stripe.invoice_paid", names.fetch("invoice_paid.recording_studio_stripe")
    assert_equal "views.recorded", names.fetch("recorded.recording_studio_views")
    refute names.key?("recordings.event_created")
  end

  def test_rules_match_conditions_and_ignore_other_sources
    @configuration.conversion :purchase do
      source "stripe.invoice_paid"
      condition :first_payment, equals: true
      condition :trial_fee, equals: false
    end
    rule = @configuration.rules.first
    paid = envelope("stripe.invoice_paid", properties: { "first_payment" => true, "trial_fee" => false })
    trial_fee = envelope("stripe.invoice_paid", properties: { "first_payment" => true, "trial_fee" => true })
    omitted = envelope("stripe.invoice_paid", properties: { "first_payment" => true })

    assert rule.matches?(paid)
    refute rule.matches?(trial_fee)
    refute rule.matches?(omitted)
    other = envelope("stripe.trial_started", properties: { "first_payment" => true, "trial_fee" => false })
    refute rule.matches?(other)
  end

  def test_envelope_keeps_amount_and_drops_email
    subscription = @configuration.subscriptions.find { |item| item.canonical_name == "stripe.invoice_paid" }
    envelope = RecordingStudioConversions::Envelope.from(
      subscription,
      event_id: "evt_1",
      amount: 4900,
      currency: "usd",
      first_payment: true,
      email: "person@example.com",
      access_token: "secret"
    )

    assert_equal "evt_1", envelope.source_event_id
    assert_equal 4900, envelope.properties["amount"]
    assert_equal "usd", envelope.properties["currency"]
    assert_equal true, envelope.properties["first_payment"]
    refute envelope.properties.key?("email")
    refute envelope.properties.key?("access_token")
  end

  def test_registration_source_id_is_the_user_id
    subscription = @configuration.subscriptions.first
    user_id = "11111111-1111-4111-8111-111111111111"
    envelope = RecordingStudioConversions::Envelope.from(subscription, user_id: user_id, method: :password)

    assert_equal user_id, envelope.source_event_id
    assert_equal "User", envelope.actor_type
    assert_equal "password", envelope.properties["method"].to_s
  end

  def test_visitor_id_reads_the_current_device_key_and_does_not_mint_one
    added = false
    unless RecordingStudio.const_defined?(:RootSwitchable, false)
      root = Module.new
      root.const_set(:DeviceKey, Class.new do
        def self.fetch(*)
          raise "conversions minted a device key"
        end
      end)
      root.const_set(:Current, Class.new do
        class << self
          attr_accessor :device_key
        end
      end)
      RecordingStudio.const_set(:RootSwitchable, root)
      added = true
    end
    RecordingStudio::RootSwitchable::Current.device_key = "device-from-root-switchable"

    assert_equal "device-from-root-switchable", RecordingStudioConversions::VisitorId.current
  ensure
    RecordingStudio.send(:remove_const, :RootSwitchable) if added
  end

  private

  def envelope(name, properties:)
    subscription = @configuration.subscriptions.find { |item| item.canonical_name == name }
    RecordingStudioConversions::Envelope.from(subscription, { event_id: "evt_test", properties: properties })
  end
end
