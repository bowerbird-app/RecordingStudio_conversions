# frozen_string_literal: true

require "test_helper"
require_relative "support/fake_adapter"

class AdaptersTest < Minitest::Test
  def setup
    @configuration = RecordingStudioConversions::Configuration.new
    @configuration.register_adapter :fake, FakeAdsAdapter
    @configuration.register_adapter :server_only, ServerOnlyAdapter
    @configuration.destination :ads, adapter: :fake, access_token: "super-secret", pixel_id: "px_1"
  end

  def test_registry_enables_only_destinations
    assert_equal %i[fake server_only], @configuration.adapters.keys
    assert_equal [FakeAdsAdapter], @configuration.enabled_adapters
    assert_equal FakeAdsAdapter, @configuration.adapter_for(:ads)
    assert_equal "px_1", @configuration.destination_for(:ads).options[:pixel_id]
  end

  def test_diagnostics_omit_destination_secrets
    payload = @configuration.to_h
    published = @configuration.destination_for(:ads).to_h

    assert_equal [:ads], payload.fetch(:destinations)
    assert_equal %i[fake server_only], payload.fetch(:adapters)
    assert_equal({ key: :ads, adapter: :fake }, published)
    refute_includes payload.to_s, "super-secret"
    refute_includes published.to_s, "super-secret"
  end

  def test_a_fresh_configuration_has_no_providers
    configuration = RecordingStudioConversions::Configuration.new

    assert_empty configuration.adapters.keys
    assert_empty configuration.destinations
    assert_empty configuration.enabled_adapters
  end

  def test_clear_adapters_drops_destinations
    @configuration.clear_adapters!

    assert_empty @configuration.adapters.keys
    assert_empty @configuration.destinations
  end

  def test_field_contract_keeps_optional_identifiers_from_blocking_a_trial
    adapter = @configuration.adapter_for(:ads)
    click = adapter.attribution_fields.find { |field| field.name == :click_id }

    assert_equal :strip, click.transform
    assert_equal 90.days, click.retention
    assert_equal [:backup_click_id], click.alternatives
    assert_equal :advertising, click.consent_category
    assert click.required_for?("stripe.invoice_paid")
    refute click.required_for?("stripe.trial_started")
    refute adapter.respond_to?(:strip)

    assert adapter.sufficient?([:external_id], event_name: "stripe.trial_started")
    refute adapter.sufficient?([], event_name: "stripe.trial_started")
  end

  def test_conditional_requirement_accepts_an_alternative_on_that_channel
    adapter = @configuration.adapter_for(:ads)

    refute adapter.sufficient?([:external_id], event_name: "stripe.invoice_paid", channel: :server)
    assert adapter.sufficient?(
      %i[external_id backup_click_id],
      event_name: "stripe.invoice_paid",
      channel: :server
    )
    assert adapter.sufficient?([:external_id], event_name: "stripe.invoice_paid", channel: :browser)
  end

  def test_consent_channels_age_and_event_names
    adapter = @configuration.adapter_for(:ads)
    rule = RecordingStudioConversions::Rule.build(:trial) { source "stripe.trial_started" }
    now = Time.utc(2026, 10, 19, 12)

    assert_equal :advertising, adapter.consent.category
    assert adapter.consent.collection
    assert adapter.consent.delivery
    assert_equal %i[server browser], adapter.delivery_channels
    assert_equal "fake-ads", adapter.browser_module
    assert_equal 7.days, adapter.max_event_age
    assert_equal "StartTrial", adapter.event_name_for(rule)
    assert_nil adapter.event_name_for("views.recorded")
    assert adapter.within_age?(now - 7.days, now: now)
    refute adapter.within_age?(now - 7.days - 1, now: now)
    refute adapter.within_age?("2026-10-19", now: now)

    other = @configuration.adapters.fetch(:server_only)
    assert_equal [:server], other.delivery_channels
    assert_nil other.browser_module
    assert_nil other.max_event_age
    refute other.consent.collection
    assert other.within_age?(now - 10.years, now: now)
    assert_equal :public, other.attribution_fields.first.sensitivity
  end

  def test_registration_rejects_incomplete_or_duplicate_providers
    assert_raises(ArgumentError) { @configuration.register_adapter :fake, FakeAdsAdapter }
    assert_raises(ArgumentError) { @configuration.register_adapter :other, FakeAdsAdapter }
    assert_raises(ArgumentError) { @configuration.destination :ads, adapter: :fake }
    assert_raises(ArgumentError) { @configuration.destination :missing, adapter: :nope }

    half = Class.new(RecordingStudioConversions::Adapters::Base) do
      key :half
      consent category: :advertising
    end
    assert_raises(ArgumentError) { @configuration.register_adapter :half, half }
  end

  def test_declarations_reject_unknown_or_incomplete_fields
    assert_raises(ArgumentError) { declare_field(source: :header, required: false, sensitivity: :identifier) }
    assert_raises(ArgumentError) { declare_field(source: :cookie, sensitivity: :identifier) }
    assert_raises(ArgumentError) { declare_field(source: :cookie, required: false, sensitivity: :secret) }
    assert_raises(ArgumentError) do
      declare_field(source: :cookie, required: false, sensitivity: :identifier, pixel: "x")
    end
    assert_raises(ArgumentError) { declare_self_alternative }
    assert_raises(ArgumentError) { declare_required_outside_events }
    assert_raises(ArgumentError) do
      declare_field(source: :cookie, required: false, sensitivity: :identifier, retention: 90)
    end
    assert_raises(ArgumentError) do
      declare_field(source: :cookie, required: false, sensitivity: :identifier, channels: [:email])
    end
  end

  def test_fields_need_consent_and_channels_must_be_known
    assert_raises(ArgumentError) do
      Class.new(RecordingStudioConversions::Adapters::Base) do
        attribution do
          field :click_id, source: :cookie, required: false, sensitivity: :identifier
        end
      end
    end

    assert_raises(ArgumentError) do
      Class.new(RecordingStudioConversions::Adapters::Base) do
        consent category: :advertising
        delivery_channels :email
      end
    end
  end

  def test_library_does_not_call_a_provider_or_forbidden_gems
    sources = Dir[File.expand_path("../lib/**/*.rb", __dir__)]
    text = sources.map { |path| File.read(path) }.join

    refute_includes text, "graph.facebook.com"
    refute_includes text, "Net::HTTP"
    refute_includes text, "MetaAdapter"
    refute_includes text, "recording_studio_attachable"
    refute_includes text, "recording_studio_library"
    refute_includes text.downcase, "attachable"
  end

  private

  def declare_self_alternative
    declare_field(
      source: :cookie,
      required: false,
      sensitivity: :identifier,
      alternatives: [:click_id],
      name: :click_id
    )
  end

  def declare_required_outside_events
    declare_field(
      source: :cookie,
      required: false,
      sensitivity: :identifier,
      events: ["stripe.trial_started"],
      required_for: ["stripe.invoice_paid"]
    )
  end

  def declare_field(name: :click_id, **options)
    owner = Class.new(RecordingStudioConversions::Adapters::Base)
    owner.consent category: :advertising
    owner.delivery_channels :server, :browser
    owner.attribution { field name, **options }
  end
end
