# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/catalog_ads_adapter"

class BrowserTrackerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioConversions.configuration.clear_adapters!
    RecordingStudioConversions.configuration.register_adapter :catalog, CatalogAdsAdapter
    RecordingStudioConversions.configuration.destination :catalog, adapter: :catalog, access_token: "secret-token"
    RecordingStudioConversions.configuration.collection_context = nil
    RecordingStudioConversions.configuration.collection_resolvers.clear
    @visitor = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    RecordingStudio::RootSwitchable::Current.reset
  end

  teardown do
    RecordingStudioConversions.configuration.clear_adapters!
    RecordingStudioConversions.configuration.clear_rules!
    RecordingStudioConversions.configuration.collection_context = nil
    RecordingStudioConversions.configuration.collection_resolvers.clear
    RecordingStudio::RootSwitchable::Current.reset
    RecordingStudioConversions::RateLimitStore.store = nil
  end

  test "the host layout opts in and a page without the helper does not" do
    get new_user_session_path

    assert_response :success
    refute_includes response.body, "recording-studio-conversions"
    refute_includes response.body, "recording_studio_conversions/tracker"

    sign_in confirmed_user
    get root_path

    assert_response :success
    assert_includes response.body, 'id="recording-studio-conversions"'
    assert_includes response.body, "recording_studio_conversions/tracker"
    refute_includes response.body, "secret-token"
    refute_includes response.body, "fake-ads.js"
    refute_match(/<script[^>]+fake-ads/, response.body)
    assert_includes response.body, "click_id"
  end

  test "collection stores permitted fields and refuses browser conversion claims" do
    remember_device!(@visitor)
    post "/recording_studio_conversions/consent", params: {
      category: "advertising", granted: true, provenance: { source: "browser" }
    }, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.dig("consent", "advertising")
    assert_equal "fake-ads", response.parsed_body.dig("modules", 0, "name")

    page_views = page_view_count
    post "/recording_studio_conversions/collection", params: {
      visitor_id: "client-supplied",
      conversion: "Purchase",
      occurrence_id: SecureRandom.uuid,
      amount: 2900,
      receipt: "forged",
      provider_dedup_id: "forged",
      fields: [
        { provider: "catalog", name: "click_id", value: "click-1" },
        { provider: "catalog", name: "browser_id", value: "from-js" },
        { provider: "catalog", name: "email", value: "person@example.com" },
        { provider: "not-enabled", name: "gclid", value: "nope" }
      ]
    }, headers: { "User-Agent" => "CatalogBrowser/1" }, as: :json

    assert_response :success
    assert_equal "present", response.parsed_body["visitor"]
    assert_includes response.parsed_body["ignored_claims"], "conversion"
    assert_equal 0, RecordingStudioConversions::Occurrence.count
    assert_equal page_views, page_view_count
    refute_includes Array(response.headers["Set-Cookie"]).join, "recording_studio_root_switchable_device_key"
    names = RecordingStudioConversions::AttributionObservation.pluck(:field_name)
    assert_includes names, "click_id"
    assert_includes names, "browser_id"
    assert_includes names, "user_agent"
    refute_includes names, "email"
    refute_includes names, "ip_address"
    refute_includes names, "gclid"
    assert_equal [@visitor], RecordingStudioConversions::AttributionObservation.distinct.pluck(:visitor_id)
    assert_nil response.parsed_body["provider_dedup_id"]
    assert_raises(NotImplementedError) { RecordingStudioConversions::BrowserReceipt.issue(occurrence_id: "x") }
    assert_raises(NotImplementedError) { CatalogAdsAdapter.new.dedup_id_for(nil) }
  end

  test "a missing device key records nothing and does not set a cookie" do
    post "/recording_studio_conversions/collection", params: {
      fields: [{ provider: "catalog", name: "click_id", value: "click-1" }]
    }, as: :json

    assert_response :success
    assert_equal "missing", response.parsed_body["visitor"]
    assert_equal 0, response.parsed_body["recorded"]
    refute_includes Array(response.headers["Set-Cookie"]).join, "recording_studio_root_switchable_device_key"
  end

  test "consent is granted before it can be withdrawn" do
    remember_device!(@visitor)
    post "/recording_studio_conversions/consent", params: {
      category: "advertising", granted: true, provenance: { source: "host" }
    }, as: :json
    assert_response :success
    assert_equal "browser", RecordingStudioConversions::ConsentRecord.last.provenance["source"]

    post "/recording_studio_conversions/collection", params: {
      fields: [{ provider: "catalog", name: "click_id", value: "click-1" }]
    }, as: :json
    assert_equal 1, RecordingStudioConversions::AttributionObservation.where(field_name: "click_id").count

    post "/recording_studio_conversions/consent", params: { category: "advertising", granted: false }, as: :json
    post "/recording_studio_conversions/collection", params: {
      fields: [{ provider: "catalog", name: "click_id", value: "click-2" }]
    }, as: :json

    assert_equal ["click-1"], RecordingStudioConversions::AttributionObservation.where(field_name: "click_id").pluck(:value)
  end

  test "consent rejects an unknown category and a non-boolean grant" do
    remember_device!(@visitor)
    post "/recording_studio_conversions/consent", params: { category: "not-a-category", granted: true }, as: :json
    assert_response :unprocessable_entity

    post "/recording_studio_conversions/consent", params: { category: "advertising", granted: "yes" }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, RecordingStudioConversions::ConsentRecord.count
  end

  test "collection and consent keep forgery protection" do
    filters = RecordingStudioConversions::ApplicationController._process_action_callbacks
    assert(filters.any? { |callback| callback.kind == :before && callback.filter == :verify_authenticity_token })
    assert RecordingStudioConversions::CollectionController.forgery_protection_strategy
    assert RecordingStudioConversions::ConsentController.forgery_protection_strategy

    app_config = Rails.application.config.action_controller
    previous = app_config.allow_forgery_protection
    app_config.allow_forgery_protection = true
    protected_controllers.each { |controller| controller.allow_forgery_protection = true }
    remember_device!(@visitor)
    assert_equal 422, post_status("/recording_studio_conversions/consent", { category: "advertising", granted: true })
    assert_equal 422, post_status("/recording_studio_conversions/collection", { fields: [] })
    assert_equal 0, RecordingStudioConversions::ConsentRecord.count
  ensure
    app_config.allow_forgery_protection = previous if app_config
    protected_controllers.each { |controller| controller.allow_forgery_protection = previous }
  end

  test "provider modules load only after consent and the collector reads server sources" do
    get "/recording_studio_conversions/modules/fake-ads"
    assert_response :forbidden
    assert_equal "private", response.headers["Cache-Control"]
    assert_equal "Cookie", response.headers["Vary"]

    remember_device!(@visitor)
    post "/recording_studio_conversions/consent", params: { category: "advertising", granted: true }, as: :json
    get "/recording_studio_conversions/modules/fake-ads"
    assert_response :success
    assert_equal "private", response.headers["Cache-Control"]
    assert_equal "Cookie", response.headers["Vary"]
    assert_includes response.body, "RecordingStudioConversionsProviderModules"
    refute_includes response.body, "fbq"

    get "/recording_studio_conversions/modules/other-ads"
    assert_response :not_found

    RecordingStudioConversions.configuration.collection_resolver(:plan) { |_context| "pro" }
    RecordingStudioConversions.configuration.collection_context = lambda do |_request, _user|
      { workspace: { "workspace_plan" => "studio" } }
    end
    request = Struct.new(:session, :user_agent, :referrer, :path, :remote_ip).new(
      { "note" => "from-session" }, "CatalogBrowser/1", nil, "/pricing", "127.0.0.1"
    )
    request.session.define_singleton_method(:id) { "raw-session" }
    RecordingStudio::RootSwitchable::Current.device_key = @visitor
    RecordingStudioConversions::Collector.call(
      request: request,
      payload: { "fields" => [{ "provider" => "catalog", "name" => "note", "value" => "from-browser" }] },
      user: nil
    )
    values = RecordingStudioConversions::AttributionObservation.pluck(:field_name, :value).to_h
    assert_equal "pro", values["plan"]
    assert_equal "studio", values["workspace_plan"]
    assert_equal "from-session", values["note"]
  end

  test "an authenticated collection links the confirmed user without a marketing field" do
    user = confirmed_user
    remember_device!(@visitor)
    post user_session_path, params: { user: { email: user.email, password: "Password123" } }
    assert_response :redirect

    post "/recording_studio_conversions/collection", params: { fields: [] }, as: :json

    link = RecordingStudioConversions::IdentityLink.find_by!(user_id: user.id)
    assert_equal @visitor, link.visitor_id
    assert link.confirmed
    assert_nil link.auth_method
  end

  test "a class-level actor resolver receives the controller" do
    user = confirmed_user
    previous = RecordingStudio.configuration.actor
    resolver = Class.new do
      def self.call(controller)
        controller.signed_in_user
      end
    end
    RecordingStudio.configuration.actor = resolver
    controller = Object.new
    controller.define_singleton_method(:signed_in_user) { user }

    assert_equal user, RecordingStudioConversions::SignedInActor.resolve(controller)
  ensure
    RecordingStudio.configuration.actor = previous
  end

  test "a zero-arity actor lambda still resolves and a resolver error is logged once" do
    user = confirmed_user
    previous = RecordingStudio.configuration.actor
    RecordingStudio.configuration.actor = -> { user }
    assert_equal user, RecordingStudioConversions::SignedInActor.resolve(Object.new)

    messages = []
    logger = Logger.new(StringIO.new)
    logger.define_singleton_method(:error) { |message| messages << message }
    old_logger = Rails.logger
    Rails.logger = logger
    RecordingStudioConversions::SignedInActor.instance_variable_set(:@resolver_error_logged, false)
    RecordingStudio.configuration.actor = ->(*) { raise "actor blew up" }
    assert_nil RecordingStudioConversions::SignedInActor.resolve(Object.new)
    assert_nil RecordingStudioConversions::SignedInActor.resolve(Object.new)
    assert_equal ["[RecordingStudioConversions] actor resolver failed: RuntimeError"], messages
  ensure
    RecordingStudio.configuration.actor = previous
    Rails.logger = old_logger if old_logger
  end

  test "collection and consent rate limits use the configured cache store" do
    remember_device!(@visitor)
    previous = RecordingStudioConversions::RateLimitStore.store
    RecordingStudioConversions::RateLimitStore.store = ActiveSupport::Cache::MemoryStore.new

    60.times do
      post "/recording_studio_conversions/consent", params: { category: "advertising", granted: true }, as: :json
      assert_response :success
    end
    post "/recording_studio_conversions/consent", params: { category: "advertising", granted: false }, as: :json
    assert_response :too_many_requests

    60.times do
      post "/recording_studio_conversions/collection", params: { fields: [] }, as: :json
      assert_response :success
    end
    post "/recording_studio_conversions/collection", params: { fields: [] }, as: :json
    assert_response :too_many_requests
  ensure
    RecordingStudioConversions::RateLimitStore.store = previous
  end

  test "a blocked browser script still leaves the registration occurrence" do
    user = confirmed_user
    RecordingStudio::RootSwitchable::Current.device_key = @visitor
    RecordingStudioConversions.configuration.conversion :registration do
      source "users.registered"
    end

    ActiveSupport::Notifications.instrument(
      "registration.completed.recording_studio_user",
      user_id: user.id,
      method: :password
    )

    occurrence = RecordingStudioConversions::Occurrence.find_by!(source_event_id: user.id)
    assert_equal "matched", occurrence.outcome
    assert_equal 0, RecordingStudioConversions::AttributionObservation.count
    assert RecordingStudioConversions::IdentityLink.exists?(user_id: user.id)
  end

  private

  def confirmed_user
    User.create!(
      email: "person-#{SecureRandom.hex(4)}@example.com",
      password: "Password123",
      password_confirmation: "Password123",
      confirmed_at: Time.current
    )
  end

  def remember_device!(value)
    name = RecordingStudioRootSwitchable.configuration.device_key_cookie_name
    jar = ActionDispatch::TestRequest.create(Rails.application.env_config).cookie_jar
    jar.encrypted[name] = value
    cookies[name.to_s] = jar[name.to_s]
  end

  def post_status(path, params)
    post path, params: params, as: :json
    response.status
  rescue ActionController::InvalidAuthenticityToken
    422
  end

  def protected_controllers
    [
      ActionController::Base,
      RecordingStudioConversions::ApplicationController,
      RecordingStudioConversions::CollectionController,
      RecordingStudioConversions::ConsentController
    ]
  end

  def page_view_count
    return 0 unless defined?(RecordingStudioViews::PageView)
    return 0 unless RecordingStudioViews::PageView.table_exists?

    RecordingStudioViews::PageView.count
  end
end
