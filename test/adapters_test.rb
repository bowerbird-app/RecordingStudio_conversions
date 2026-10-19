# frozen_string_literal: true

require "test_helper"
require "json"
require "pp"
require "fileutils"
require "tmpdir"
require "zeitwerk"
require_relative "support/fake_adapter"

class AdaptersTest < Minitest::Test
  def setup
    @configuration = RecordingStudioConversions::Configuration.new
    @configuration.register_adapter :fake, FakeAdsAdapter
    @configuration.register_adapter :server_only, ServerOnlyAdapter
    @configuration.destination :ads, adapter: :fake, access_token: "super-secret", pixel_id: "px_1"
  end

  def teardown
    return unless @restore_configuration_set

    RecordingStudioConversions.instance_variable_set(:@configuration, @restore_configuration)
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
    destination = @configuration.destination_for(:ads)
    restored = RecordingStudioConversions::Adapters::Destination.new(**published, options: destination.options)
    assert_equal :fake, restored.adapter_key
    assert_equal "px_1", restored.options[:pixel_id]
    assert_equal "super-secret", destination.deconstruct_keys(nil).dig(:options, :access_token)
    assert_equal "super-secret", destination.deconstruct.last[:access_token]
    dumped = Marshal.load(Marshal.dump(destination))
    assert_equal "super-secret", dumped.options[:access_token]
  end

  def test_inspect_and_pretty_print_redact_destination_secrets
    destination = @configuration.destination_for(:ads)
    rendered = PP.pp(@configuration, +"")
    generated = JSON.generate(destination)

    refute_includes destination.inspect, "super-secret"
    refute_includes destination.to_s, "super-secret"
    refute_includes "#{destination}", "super-secret" # rubocop:disable Style/RedundantInterpolation
    refute_includes generated, "super-secret"
    refute_includes @configuration.inspect, "super-secret"
    refute_includes @configuration.to_s, "super-secret"
    refute_includes "#{@configuration}", "super-secret" # rubocop:disable Style/RedundantInterpolation
    refute_includes JSON.generate(@configuration), "super-secret"
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
    refute other.within_age?(nil, now: now)
    refute other.within_age?("2026-10-19", now: now)
    assert_equal :public, other.attribution_fields.first.sensitivity
  end

  def test_delivery_methods_raise_until_a_later_milestone
    adapter = @configuration.adapter_for(:ads).new(destination: @configuration.destination_for(:ads))
    assert_same @configuration.destination_for(:ads), adapter.destination
    assert_nil @configuration.adapter_for(:ads).new.destination

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
      conversion_event "purchase", as: "Purchase"
      attribution do
        field :click_id, source: :query_parameter, required: false, sensitivity: :identifier
      end
    end
    child = Class.new(parent) do
      key :child_ads
      conversion_event "first_purchase", as: "Subscribe"
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

  def test_subclasses_can_override_inherited_declarations_once
    parent = named_adapter(:OverrideParent) do
      key :override_parent
      consent category: :advertising
      delivery_channels :server
      max_event_age 1.day
      browser_module "parent-ads"
    end
    child = Class.new(parent) do
      consent category: :analytics, collection: false
      delivery_channels :browser
      max_event_age 2.days
      browser_module "child-ads"
    end
    self.class.const_set(:OverrideChild, child)

    assert_equal :analytics, child.consent.category
    refute child.consent.collection
    assert_equal [:browser], child.delivery_channels
    assert_equal 2.days, child.max_event_age
    assert_equal "child-ads", child.browser_module
    assert_equal :advertising, parent.consent.category
    assert_equal [:server], parent.delivery_channels
    assert_equal 1.day, parent.max_event_age
    assert_equal "parent-ads", parent.browser_module

    error = assert_raises(ArgumentError) { child.consent category: :advertising }
    assert_match(/already declared/, error.message)
    assert_raises(ArgumentError) { child.delivery_channels :server }
    assert_raises(ArgumentError) { child.max_event_age 3.days }
    assert_raises(ArgumentError) { child.browser_module "again" }
  end

  def test_registration_rejects_incomplete_or_duplicate_providers
    @configuration.register_adapter :fake, FakeAdsAdapter
    assert_equal FakeAdsAdapter, @configuration.adapters.fetch(:fake)

    other = named_adapter(:OtherFake) do
      key :fake
      consent category: :advertising
      delivery_channels :server
    end
    duplicate = assert_raises(ArgumentError) { @configuration.register_adapter :fake, other }
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
    refute_registered_with_zeitwerk
  end

  def test_check_runs_after_a_rule_is_configured
    configuration = swapped_configuration

    RecordingStudioConversions.configure do |config|
      config.register_adapter :fake, FakeAdsAdapter
      config.conversion(:trial) { source "stripe.trial_started" }
      config.conversion(:purchase) { source "stripe.invoice_paid" }
      config.conversion(:first_purchase) { source "stripe.invoice_paid" }
    end
    boot_check!
    assert configuration.adapters.registered?(:fake)

    configuration.clear_rules!
    configuration.raise_errors = true
    configuration.conversion(:trial) { source "stripe.trial_started" }
    error = assert_raises(ArgumentError) { RecordingStudioConversions.check! }
    assert_equal missing_rule_message, error.message
  end

  def test_check_raises_a_missing_rule_when_eager_load_is_on
    configuration = missing_rule_configuration
    assert_equal false, configuration.raise_errors

    with_boot_context(eager_load: true) do |logger|
      error = assert_raises(ArgumentError) { RecordingStudioConversions.check! }
      assert_equal missing_rule_message, error.message
      assert_empty logger.warnings
    end
  end

  def test_check_warns_a_missing_rule_when_eager_load_is_off
    configuration = missing_rule_configuration
    assert_equal false, configuration.raise_errors

    with_boot_context(eager_load: false) do |logger|
      RecordingStudioConversions.check!
      assert_equal [boot_warning], logger.warnings
    end
  end

  def test_check_raises_when_raise_errors_is_true_and_eager_load_is_off
    configuration = missing_rule_configuration
    configuration.raise_errors = true

    with_boot_context(eager_load: false) do |logger|
      error = assert_raises(ArgumentError) { RecordingStudioConversions.check! }
      assert_equal missing_rule_message, error.message
      assert_empty logger.warnings
    end
  end

  def test_check_raises_when_raise_errors_is_false_and_eager_load_is_on
    configuration = missing_rule_configuration
    configuration.raise_errors = false

    with_boot_context(eager_load: true) do |logger|
      error = assert_raises(ArgumentError) { RecordingStudioConversions.check! }
      assert_equal missing_rule_message, error.message
      assert_empty logger.warnings
    end
  end

  def test_overriding_consent_retags_inherited_fields
    parent = named_adapter(:ConsentParent) do
      key :consent_parent
      consent category: :advertising
      delivery_channels :server
      attribution do
        field :click_id, source: :query_parameter, required: false, sensitivity: :identifier
      end
      identity do
        field :external_id, source: :cookie, required: true, sensitivity: :identifier
      end
    end
    child = Class.new(parent) do
      consent category: :analytics
    end
    self.class.const_set(:ConsentChild, child)

    assert_equal [:analytics], child.fields.map(&:consent_category).uniq
    assert_equal [:advertising], parent.fields.map(&:consent_category).uniq
  end

  def test_unloadable_cpath_guard_skips_a_loader_without_the_method
    assert Zeitwerk::Loader.allocate.respond_to?(:unloadable_cpath?),
           "unloadable_cpath? missing on Zeitwerk #{Zeitwerk::VERSION}"

    adapter = named_adapter(:LegacyLoaderAdapter) do
      key :legacy_loader
      consent category: :advertising
      delivery_channels :server
    end
    previous = Rails.application
    Rails.application = Struct.new(:autoloaders).new(Struct.new(:main).new(Object.new))
    @configuration.register_adapter :legacy_loader, adapter
    assert @configuration.adapters.registered?(:legacy_loader)
  ensure
    Rails.application = previous if defined?(previous)
  end

  def test_app_adapter_passes_check_when_reloading_is_off
    root = nil
    loader = nil
    previous = Rails.application
    root = Dir.mktmpdir
    app_root = File.join(root, "app")
    loader = Zeitwerk::Loader.new
    FileUtils.mkdir_p(app_root)
    write_adapter(app_root, "app_host_adapter", :app_host)
    loader.push_dir(app_root)
    loader.setup
    Rails.application = Struct.new(:autoloaders).new(Struct.new(:main).new(loader))

    adapter = AppHostAdapter
    refute loader.reloading_enabled?
    refute loader.unloadable_cpath?(adapter.name)
    configuration = RecordingStudioConversions::Configuration.new
    configuration.register_adapter :app_host, adapter
    configuration.adapters.check!(subscriptions: configuration.subscriptions, rules: configuration.rules)
    assert configuration.adapters.registered?(:app_host)
  ensure
    Rails.application = previous if defined?(previous)
    loader&.unregister
    remove_host_adapter(:AppHostAdapter)
    FileUtils.rm_rf(root) if defined?(root) && root
  end

  def test_required_managed_lib_adapter_survives_reload
    root = Dir.mktmpdir
    loader = Zeitwerk::Loader.new
    previous = Rails.application
    write_adapter(root, "managed_lib_adapter", :managed_lib)
    loader.push_dir(root)
    loader.enable_reloading
    require File.join(root, "managed_lib_adapter.rb")
    loader.setup
    Rails.application = Struct.new(:autoloaders).new(Struct.new(:main).new(loader))

    refute loader.unloadable_cpath?(ManagedLibAdapter.name)
    @configuration.register_adapter :managed_lib, ManagedLibAdapter
    loader.reload
    assert Object.const_defined?(:ManagedLibAdapter)
    assert_equal ManagedLibAdapter, @configuration.adapters.fetch(:managed_lib)
    refute loader.unloadable_cpath?(ManagedLibAdapter.name)
  ensure
    Rails.application = previous if defined?(previous)
    teardown_loader(loader)
    remove_host_adapter(:ManagedLibAdapter)
    FileUtils.rm_rf(root) if defined?(root) && root
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
    assert_match(/not a configured source/, bad_event.message)

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

  def refute_registered_with_zeitwerk
    root = Dir.mktmpdir
    stable_root = Dir.mktmpdir
    loader = Zeitwerk::Loader.new
    previous = Rails.application
    install_main_loader(loader, root)
    assert_reloadable_adapter_rejected(loader)
    assert_required_adapter_accepted(loader, stable_root)
  ensure
    Rails.application = previous if defined?(previous)
    teardown_loader(loader)
    remove_host_adapter(:ReloadableHostAdapter)
    remove_host_adapter(:StableHostAdapter)
    FileUtils.rm_rf(root) if defined?(root) && root
    FileUtils.rm_rf(stable_root) if defined?(stable_root) && stable_root
  end

  def install_main_loader(loader, root)
    write_adapter(root, "reloadable_host_adapter", :reloadable_host)
    loader.push_dir(root)
    loader.enable_reloading
    loader.setup
    Rails.application = Struct.new(:autoloaders).new(Struct.new(:main).new(loader))
  end

  def assert_reloadable_adapter_rejected(loader)
    adapter = ReloadableHostAdapter
    assert loader.unloadable_cpath?(adapter.name)
    error = assert_raises(ArgumentError) { @configuration.register_adapter :reloadable_host, adapter }
    assert_match(/reloadable/, error.message)
  end

  def assert_required_adapter_accepted(loader, stable_root)
    write_adapter(stable_root, "stable_host_adapter", :stable_host)
    require File.join(stable_root, "stable_host_adapter.rb")
    refute loader.unloadable_cpath?(StableHostAdapter.name)
    @configuration.register_adapter :stable_host, StableHostAdapter
    assert @configuration.adapters.registered?(:stable_host)
  end

  def teardown_loader(loader)
    loader&.unload
    loader&.unregister
  rescue Zeitwerk::SetupRequired
    loader&.unregister
  end

  def remove_host_adapter(name)
    Object.send(:remove_const, name) if Object.const_defined?(name)
  end

  def write_adapter(dir, file_name, key)
    File.write(File.join(dir, "#{file_name}.rb"), <<~RUBY)
      class #{file_name.camelize} < RecordingStudioConversions::Adapters::Base
        key :#{key}
        consent category: :advertising
        delivery_channels :server
      end
    RUBY
  end

  def missing_rule_configuration
    configuration = swapped_configuration
    configuration.register_adapter :fake, FakeAdsAdapter
    configuration.conversion(:trial) { source "stripe.trial_started" }
    configuration
  end

  def missing_rule_message
    "adapter fake conversion event purchase, first_purchase is not a configured rule"
  end

  def boot_warning
    "[RecordingStudioConversions] #{missing_rule_message}"
  end

  def with_boot_context(eager_load:)
    previous_application = Rails.application
    previous_logger = Rails.logger
    logger = boot_logger
    config = Struct.new(:eager_load).new(eager_load)
    Rails.application = Struct.new(:config).new(config)
    Rails.logger = logger
    yield logger
  ensure
    Rails.application = previous_application
    Rails.logger = previous_logger
  end

  def boot_logger
    logger = Object.new
    warnings = []
    logger.define_singleton_method(:warn) { |message| warnings << message }
    logger.define_singleton_method(:warnings) { warnings }
    logger
  end

  def swapped_configuration
    configuration = RecordingStudioConversions::Configuration.new
    @restore_configuration = RecordingStudioConversions.instance_variable_get(:@configuration)
    @restore_configuration_set = true
    RecordingStudioConversions.instance_variable_set(:@configuration, configuration)
    configuration
  end

  def boot_check!
    callbacks = []
    host = Object.new
    host.define_singleton_method(:config) do
      target = Object.new
      target.define_singleton_method(:after_initialize) { |&block| callbacks << block }
      target
    end
    initializer = RecordingStudioConversions::Engine.initializers.find do |entry|
      entry.name == "recording_studio_conversions.check_contracts"
    end
    host.instance_exec(&initializer.block)
    callbacks.each(&:call)
  end

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
