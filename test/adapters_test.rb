# frozen_string_literal: true

require "test_helper"
require "pp"
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
    assert_equal({ key: :ads, adapter_key: :fake }, published)
    refute_includes payload.to_s, "super-secret"
    refute_includes published.to_s, "super-secret"
    restored = RecordingStudioConversions::Adapters::Destination.new(**published, options: {})
    assert_equal :fake, restored.adapter_key
  end

  def test_inspect_and_pretty_print_redact_destination_secrets
    destination = @configuration.destination_for(:ads)
    rendered = PP.pp(@configuration, +"")

    refute_includes destination.inspect, "super-secret"
    refute_includes @configuration.inspect, "super-secret"
    refute_includes rendered, "super-secret"
    assert_includes destination.inspect, "access_token"
    assert_includes @configuration.inspect, "access_token"
    assert_includes rendered, "pixel_id"
    refute_includes destination.inspect, "px_1"
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
    refute adapter.sufficient?([:external_id], event_name: "stripe.invoice_paid", channel: nil)
    assert adapter.sufficient?(
      %i[external_id backup_click_id],
      event_name: "stripe.invoice_paid",
      channel: nil
    )
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
    purchase = RecordingStudioConversions::Rule.build(:purchase) { source "stripe.invoice_paid" }
    first = RecordingStudioConversions::Rule.build(:first_purchase) { source "stripe.invoice_paid" }
    assert_equal "Purchase", adapter.event_name_for(purchase)
    assert_equal "Subscribe", adapter.event_name_for(first)
    skew = RecordingStudioConversions::Adapters::Queries::FUTURE_CLOCK_SKEW
    assert_equal 5.minutes, skew
    assert adapter.within_age?(now - 7.days, now: now)
    refute adapter.within_age?(now - 7.days - 1, now: now)
    refute adapter.within_age?("2026-10-19", now: now)
    assert adapter.within_age?(now.to_datetime, now: now)
    assert adapter.within_age?(now + skew, now: now)
    refute adapter.within_age?(now + skew + 1, now: now)
    assert_raises(ArgumentError) { adapter.within_age?(Date.new(2026, 10, 19), now: now) }

    other = @configuration.adapters.fetch(:server_only)
    assert_equal [:server], other.delivery_channels
    assert_nil other.browser_module
    assert_nil other.max_event_age
    refute other.consent.collection
    assert other.within_age?(now - 10.years, now: now)
    refute other.within_age?(now + 6.minutes, now: now)
    assert_equal :public, other.attribution_fields.first.sensitivity
  end

  def test_delivery_methods_raise_until_a_later_milestone
    adapter = @configuration.adapter_for(:ads).new

    %i[build_payload deliver normalize_error dedup_id_for].each do |name|
      error = assert_raises(NotImplementedError) { adapter.public_send(name, Object.new) }
      assert_match(/#{name}/, error.message)
    end
  end

  def test_subclasses_keep_parent_declarations
    parent = named_adapter(:SharedAds) do
      key :shared
      consent category: :advertising
      delivery_channels :server
      max_event_age 1.day
      browser_module "parent-ads"
      event "purchase", as: "Purchase"
      attribution do
        field :click_id, source: :query_parameter, required: false, sensitivity: :identifier
      end
    end
    child = Class.new(parent) do
      key :child_ads
      event "first_purchase", as: "Subscribe"
      attribution do
        field :extra_id, source: :cookie, required: false, sensitivity: :public
      end
    end
    self.class.const_set(:ChildAds, child)

    assert_equal [:click_id], parent.fields.map(&:name)
    assert_equal %i[click_id extra_id], child.fields.map(&:name)
    assert_equal :shared, parent.key
    assert_equal :child_ads, child.key
    assert_equal "Purchase", child.event_name_for("purchase")
    assert_equal "Subscribe", child.event_name_for("first_purchase")
    assert_nil parent.event_name_for("first_purchase")
    assert_equal [:server], child.delivery_channels
    assert_equal 1.day, child.max_event_age
    assert_equal "parent-ads", child.browser_module
    assert_equal :advertising, child.consent.category
  end

  def test_registration_rejects_incomplete_or_duplicate_providers
    duplicate = assert_raises(ArgumentError) { @configuration.register_adapter :fake, FakeAdsAdapter }
    assert_match(/already registered/, duplicate.message)
    assert_raises(ArgumentError) { @configuration.register_adapter :other, FakeAdsAdapter }
    assert_raises(ArgumentError) { @configuration.destination :ads, adapter: :fake }
    assert_raises(ArgumentError) { @configuration.destination :missing, adapter: :nope }

    half = named_adapter(:HalfAdapter) do
      key :half
      consent category: :advertising
    end
    incomplete = assert_raises(ArgumentError) { @configuration.register_adapter :half, half }
    assert_match(/delivery channel/, incomplete.message)
  end

  def test_registration_rejects_anonymous_and_reloadable_adapters
    anonymous = Class.new(RecordingStudioConversions::Adapters::Base) do
      key :anon
      consent category: :advertising
      delivery_channels :server
    end
    anon_error = assert_raises(ArgumentError) { @configuration.register_adapter :anon, anonymous }
    assert_match(/anonymous/, anon_error.message)

    reloadable = named_adapter(:ReloadableAds) do
      key :reloadable
      consent category: :advertising
      delivery_channels :server
    end
    directory = File.dirname(Object.const_source_location(reloadable.name).first)
    error = nil
    RecordingStudioConversions::Adapters::Stability.stub(:reloadable_directories, [directory]) do
      error = assert_raises(ArgumentError) { @configuration.register_adapter :reloadable, reloadable }
    end
    assert_match(/reloadable/, error.message)
    assert_match(%r{lib/}, error.message)
  end

  def test_registration_checks_alternatives_and_subscription_names
    orphan = named_adapter(:OrphanAlternative) do
      key :orphan
      consent category: :advertising
      delivery_channels :server
      attribution do
        field :click_id,
              source: :query_parameter,
              required: false,
              sensitivity: :identifier,
              alternatives: [:backup_click_id]
      end
    end
    missing = assert_raises(ArgumentError) { @configuration.register_adapter :orphan, orphan }
    assert_match(/backup_click_id/, missing.message)
    assert_match(/not declared/, missing.message)

    unknown = named_adapter(:UnknownEvent) do
      key :unknown_event
      consent category: :advertising
      delivery_channels :server
      attribution do
        field :ref_id,
              source: :query_parameter,
              required: false,
              sensitivity: :public,
              events: ["not.subscribed"]
      end
    end
    bad_event = assert_raises(ArgumentError) { @configuration.register_adapter :unknown_event, unknown }
    assert_match(/not a subscription/, bad_event.message)

    skipped = RecordingStudioConversions::Configuration.new
    skipped.subscriptions.clear
    skipped.register_adapter :unknown_event, unknown
    assert skipped.adapters.registered?(:unknown_event)
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

  def named_adapter(const_name, &)
    klass = Class.new(RecordingStudioConversions::Adapters::Base, &)
    self.class.const_set(const_name, klass)
    klass
  end

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
