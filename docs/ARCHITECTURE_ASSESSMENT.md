# Architecture assessment — Recording Studio Conversions

Milestone 1 only. This document records how `docs/INSTRUCTION.md` lines up with the Recording Studio gems it depends on. No conversion engine, adapter, migration, or browser tracker is implemented here.

Inspection date: 2026-10-19. Each repository below was a `--depth 1` clone of its default branch. File paths are paths inside that clone. A claim that names a path and a commit was read from that tree. Anything not read that way is marked **unverified**.

`RecordingStudio_attachable` and `RecordingStudio_library` were not inspected and are not proposed for change. No dependency on either gem showed up in the trees that were read. See open question 1.

## Repositories read

| Repository | Default-branch commit | What it is today |
|---|---|---|
| `bowerbird-app/RecordingStudio` | `613501164c57b6f0bf6e8e356d593b1e5c151368` | Core recordings and history. Tag `v4.7.0` points at this same commit (`git ls-remote`). This conversions repo's `Gemfile` pins that tag. |
| `bowerbird-app/RecordingStudio_views` | `b57b35ad9f92fb058228bd6c16e591fb5f4afd7e` | Still the unmodified gem template (`lib/gem_template.rb`, module `GemTemplate`). Commit subject is "Initial commit" (2026-10-19). There is no page-view collector. |
| `bowerbird-app/RecordingStudio_logs` | `a8e936a924101c4e6c250f46c11af794b8118707` | Partitioned logs, daily aggregations, optional Metrics bridge, read-only Admin screens. |
| `bowerbird-app/RecordingStudio_metrics` | `710afbc0f0ef03025c52520174770a5cf4b79118` | Metric registry and `execute`. |
| `bowerbird-app/RecordingStudio_admin` | `10cefdf61198504d3c445536f769b64ac923bf2b` | Screen, section, widget, and resource DSL. Access checks go through Accessible. |
| `bowerbird-app/RecordingStudio_accessible` | `b3941165d0196ae143a5edecc532bc135d92c7d2` | Recording roles and named action keys. |
| `bowerbird-app/RecordingStudio_stripe` | `5c818de23c833d5f0a4e8edf9cdd85280d27b14a` | Checkout, subscriptions, invoices, webhook idempotency. No domain notification events. |
| `bowerbird-app/RecordingStudio_users` | `401af0c44f1c00c4c01d175e2d54b18c64dff143` | Devise users, OTP, OAuth identities, registration notification. |
| `bowerbird-app/RecordingStudio_notifications` | `d7ce744a5b8e074b6770f12d3399636c99367dbd` | Notify and deliver notifications. Not a conversion source. |
| `bowerbird-app/RecordingStudio_pages` | `9322768fa84fda41de14130972eb27af8643084d` | Page recordables. No advertising or view event. |
| `bowerbird-app/RecordingStudio_presskits` | `71fb1602ddcb60ec925f6aa52539db3288a52ba8` | Press-kit visibility. No page-view event. |
| `bowerbird-app/RecordingStudio_publishable` | `52e05f838308ef807349ce1180cbce16bd0e4835` | After-commit publish lifecycle notifications. |
| `bowerbird-app/RecordingStudio_downloadable` | `615376a5ee04ab878b3ba14ab71bdf79fdafb719` | Append-only download log owned by that gem. Not registered with Logs. |
| `bowerbird-app/flatpack` | `530eb3ec9bf9901a6832d663a92236920eaa6842` | UI kit. Stimulus controllers under `app/javascript/flat_pack/controllers/`. |
| `bowerbird-app/RecordingStudio_onboarding` | `c8f66f9afc132ec3648c308d23d27a0baa6b1a1c` | Read because Users documents it as the consumer of the registration event. Not a conversion domain. |

Dummy-app pins inside Metrics (`README.md` companion tags) were not checked out. Assessment of Metrics, Admin, Accessible, Stripe, Pages, and Downloadable is against the default-branch SHAs above, which may differ from those tags. **Unverified** against the pinned tags.

## 1. Reusable mechanisms

### Event emission and subscription

Core history is `RecordingStudio.record!` in `lib/recording_studio.rb` (`6135011`). Inside `RecordingStudio::Recording.transaction` it writes `recording_studio_events`, then calls `instrument_event`, then `RecordingStudio::Hooks.run(:after_record, event)`. `instrument_event` publishes ActiveSupport Notifications name `"recordings.event_created"` when `configuration.event_notifications_enabled` is true. The default is true (`lib/recording_studio/configuration.rb`). Payload:

- `schema_version` (integer `1`)
- `event_id`, `recording_id`, `root_recording_id`
- `action`
- `recordable_type`, `recordable_id`, `previous_recordable_type`, `previous_recordable_id`
- `actor_type`, `actor_id`, `impersonator_type`, `impersonator_id`
- `occurred_at`

There is no separate subscribe API. Subscribers use `ActiveSupport::Notifications.subscribe("recordings.event_created")`, as the dummy does in `test/dummy/config/initializers/recording_studio_notifications.rb`.

Idempotency is per recording: unique index `index_recording_studio_events_on_recording_and_idempotency_key` on `(recording_id, idempotency_key)` where the key is present (`db/install_migrate/20250101000002_create_recording_studio_events.rb`). `configuration.idempotency_mode` defaults to `:return_existing`. `Recording#log_event!` (`app/models/recording_studio/recording.rb`) is a thin call to `record!` with the current recordable, so it emits the same notification. It is history, not a domain-event bus.

`RecordingStudio::Hooks.after_record` (`lib/recording_studio/hooks.rb`) runs in the same transaction, before commit. A subscriber that does external work from `"recordings.event_created"` can observe an event whose transaction later rolls back. There is no transactional outbox in core.

Publishable is the pattern to copy for domain events. `RecordingStudioPublishable::LifecycleNotifications` (`lib/recording_studio_publishable/lifecycle_notifications.rb`, `52e05f8`) defines:

- `"published.recording_studio_publishable"`
- `"unpublished.recording_studio_publishable"`
- `"revised.recording_studio_publishable"`

`subscribe` wraps `ActiveSupport::Notifications.subscribe`. `emit_after_commit` uses `ActiveRecord.after_all_transactions_commit`. Payload includes `schema_version`, `recording_id`, `recordable_type`, `recordable_id`, `actor_type`, `actor_id`, `occurred_at`, `source`, and previous/current publish state. The file states that `"recordings.event_created"` is snapshot history and that these notifications are the cross-gem signal.

Users registration uses the same after-commit helper. See section 1, Users.

**Reuse:** Conversions subscribes with `ActiveSupport::Notifications.subscribe`. It does not subscribe to every `"recordings.event_created"`. Domain gems that need a conversion emit their own after-commit notification, following Publishable and `RegistrationCompleted`. Core `record!` / `log_event!` / idempotency stay the history mechanism and are not the conversion bus.

**Gap:** no shared event registry, schema catalogue, or outbox gem exists. Conversions owns its subscription list and canonical envelope. Financial durability has to be built at the producer (Stripe webhook row) and at the conversion occurrence, not by waiting for a core outbox.

### Views page-view events

`RecordingStudio_views` at `b57b35a` contains `lib/gem_template.rb` and the template README ("Internal template for building Rails engine addons"). No view model, no collector, no notification.

Logs documents a **dummy** site-view pipeline, not a Views gem. `docs/guides/site-views-press-kits.md` (`a8e936a`) describes a partitioned `site_views` table in the Logs dummy, with Press Kit and Press Center aggregations. The guide says press centers do not have a gem and the dummy stands in. `RecordingStudioLogs.aggregate` example name `"presskits/press_kit_views"` in `README.md` is a registration example. Presskits at `71fb160` does not call `RecordingStudioLogs`.

**Reuse:** the Logs producer contract, once a real Views gem exists and registers its table. Conversions consumes a Views notification. It does not insert page-view rows and it does not register a second page-view log.

### Logs

Public API in `lib/recording_studio_logs.rb` (`a8e936a`):

- `RecordingStudioLogs.register(...)` → `Registry#register_log`
- `RecordingStudioLogs.aggregate(...)` → `Registry#register_aggregation`
- `RecordingStudioLogs.finalize!` also calls `MetricsBridge.register!`
- `aggregate_day!`, `backfill!`, `reconcile!`, `cleanup_retention!`, `delete_for_root`

`LogRegistration` (`lib/recording_studio_logs/log_registration.rb`) takes `model:`, `timestamp_column:`, `partition_interval:` (`:monthly` or `nil`), `retention:` (`:indefinite` or a duration), `root_column:`, `owner:`, and `aggregatable:` column grants. A string model name stays dormant until that class loads. A second owner cannot take the same model or aggregation name (`Registry#reject_other_owner!`).

`AggregationDefinition` names match `owner/purpose` (`presskits/press_kit_views`). Filters are equality. Grouping and measurements must be in the producer contract (`ColumnContract`: filter `:eq`; measurements `:sum`, `:average`, `:minimum`, `:maximum`; `:count` needs no column). Interval is daily UTC. Rebuilding a day replaces that day's summary rows.

`Schema.partitioned_log` creates a table partitioned by the timestamp, primary key `(id, timestamp)`, UUID `id` default `gen_random_uuid()`. `Schema.root_and_time_index` and `Schema.summary_index` (`nulls_not_distinct: true`) are the index helpers. `EnsuresPartition` creates a missing month on insert. `Retention::OwnerDeletion` deletes rows for one `root_recording_id` and rebuilds affected summary days.

`MetricsBridge` publishes rooted `:count` and `:sum` measurements as Metrics timeseries when Metrics is loaded. The resource name is the aggregation name with `/` replaced by `_` (for example `presskits_press_kit_views`).

Admin catalogue is read-only: `lib/recording_studio_logs/admin.rb` registers section `"logs"` and screens `"log_health"`, `"log_detail"`, `"summaries"`, `"summary_detail"`.

**Reuse for Conversions:** register one operational log for matched-conversion and delivery diagnostics (shorter retention), with `root_column: :root_recording_id` so `delete_for_root` works. Register aggregations such as `conversions/events_received` only for columns the producer declares. High-volume page views stay in the Views log. Pending delivery rows are ordinary Conversions tables, not log partitions, so log retention cannot delete a queued delivery.

Downloadable's `DownloadLog.record!` (`app/models/recording_studio_downloadable/download_log.rb`, `615376a`) is a separate append-only table. It does not call `RecordingStudioLogs.register`. It is not the logging API to copy into Conversions.

### Metrics

`RecordingStudioMetrics.register(resource, model:, blast_radius:, scope:, scope_attribute:, api_authorize:, &)` and `RecordingStudioMetrics.execute(identifier, context:, **params)` (`lib/recording_studio_metrics.rb`, `710afbc`). DSL methods: `count`, `sum`, `average`, `breakdown`, `timeseries`, `custom` (`lib/recording_studio_metrics/dsl.rb`). Identifiers look like `"members.total"`. `discover` returns catalogue metadata visible to a context. API exposure is opt-in via `expose_to_api`.

`Context` scopes are `:recording`, `:root`, and `:site` (`lib/recording_studio_metrics/context.rb`). Scope comes from the trusted context, not from metric filters.

**Reuse:** Conversions registers its own metrics on occurrence and delivery tables (counts by status, provider, latency). It leaves the Logs bridge to publish UTC-day rollups. It does not add metric types to the Metrics gem.

### Admin read-only DSL

`RecordingStudioAdmin.register_screen`, `register_section`, `register_widget`, `register_resource` (`lib/recording_studio_admin.rb`, `10cefdf`). Screen class API (`lib/recording_studio_admin/screen.rb`): `key`, `title`, `subtitle`, `query`, `chart`, `table`, `widget`, `summary`, `availability_scope`, `allow_export`. Section and widget use the same `key` / `title` style (`Definitions::Base`).

`Resource.action` (`lib/recording_studio_admin/resource.rb`) can set `method:` and `destructive:`. A non-GET method is a write. Logs screens only use table `action :open` with a GET path (`lib/recording_studio_logs/admin/screens.rb`). That is the read-only pattern.

Authorization (`lib/recording_studio_admin/authorization.rb`) calls `RecordingStudioAccessible.authorized?(actor:, recording:, role:)`. Default `required_access_role` is `:view` (`lib/recording_studio_admin/configuration.rb`). The access recording must match the current root.

`AdminActionAudit` instruments `"admin_action.recording_studio_admin"` when an audited resource action is recorded (`NOTIFICATION_NAME` in `lib/recording_studio_admin/admin_action_audit.rb`). That audit event is not a conversion source.

**Reuse:** Conversions defines screens and widgets in its own engine and calls `register_screen` / `register_section` / `register_widget` when Admin is loaded, the way `RecordingStudioLogs::Admin.register!` does. Screens use `query` and `table` only. No `Resource.action` with a non-GET method. Rules, providers, and destinations stay in Ruby.

### Accessible resource keys

Accessible has two different key spaces. Both were read. There is no table of "admin resource keys" inside Accessible.

1. **Ranked and declared roles** on a recording. `RecordingStudioAccessible.authorized?`, `authorized_for_role?`, `authorized_for_any_role?`, `roles_for` (`lib/recording_studio_accessible.rb`, `b394116`). Admin uses `authorized?` with a role, default `:view`.

2. **Named action keys**, symbols, often namespaced. `ActionRegistry#register` stores metadata (`name`, `label`, `description`, `source`, `recording_required`). `define` stores the policy. `authorized?` on the registry fails closed (`lib/recording_studio_accessible/action_registry.rb`). README examples (`README.md` around the "Authorizing named actions" section): `:"recording_studio_messages.create_group"`, `:subscribed`, `:"recording_studio_exportable.export"`, `:"recording_studio_publishable.publish"`, `:"recording_studio_duplicatable.duplicate"`. Introspection: `registered_actions`, `action_registration_for`, `defined_actions`.

Press kits registers an audience action, not a view counter: `RecordingStudioPresskits::Visibility::ACTION = :"presskits.kit_view_full"` (`lib/recording_studio_presskits/visibility.rb`, `71fb160`). `register_action!` writes `configuration.action_audiences`. That answers "who may see the kit", not "a view was recorded".

**Reuse:** Admin monitoring stays on role `:view` (or a host-chosen role) against the admin access recording. If a host must distinguish "may see conversion operations" from ordinary view, Conversions registers one action key such as `:"recording_studio_conversions.view_operations"` through `RecordingStudioAccessible.register_action` / `define_action` in the Conversions engine. That does not require a change to the Accessible gem.

### Stripe subscription and payment events

Stripe persists billing state and does not emit ActiveSupport domain events. A search of `*.rb` under the Stripe repo found no `ActiveSupport::Notifications.instrument`.

`ProcessWebhook::EVENT_HANDLERS` (`lib/recording_studio_stripe/process_webhook.rb`, `5c818de`):

- `checkout.session.completed`, `checkout.session.async_payment_succeeded` → `ApplySubscription` or `ApplyAllowance`
- `customer.subscription.created`, `customer.subscription.updated` → `ApplySubscription` with Stripe `status`
- `customer.subscription.deleted` → local status `"canceled"`
- `invoice.paid` → if the local subscription is `"past_due"`, set `"active"`. Any other invoice is ignored
- `invoice.payment_failed` → status `"past_due"`
- product and price catalogue events

Idempotency: `recording_studio_stripe_webhook_events.stripe_id` is unique. A repeat returns `:duplicate`. The stored payload is only `id`, `type`, `created`, `object_id`, `livemode` (`event_payload`). Amount, currency, and customer email from the Stripe object are not kept.

`ApplySubscription` (`lib/recording_studio_stripe/apply_subscription.rb`) writes `recording_studio_stripe_subscriptions` and finds or creates `recording_studio_stripe_customers`. Customer columns (`test/dummy/db/schema.rb`): `email`, `root_recording_id` (unique), `stripe_id` (unique). There is no `user_id`. Subscription columns: `status`, `stripe_id` (unique), `root_recording_id`, `customer_id`, `price_id`, period timestamps, `subscription_type`, `metadata`. One live subscription per root and type, where status is `active`, `trialing`, or `past_due`. Stale events are dropped by comparing `metadata["stripe_event_created"]`.

Trial configuration lives on product metadata (`trial_days`, `trial_unit_amount`) via `RecordingStudioStripe::Trial` (covered by `test/trial_test.rb`). A live trial is the Stripe status string `"trialing"` stored on the subscription. Nothing records the transition into that status.

Prices carry `unit_amount` and `currency`. `handle_invoice_paid` does not read them. A first successful payment on an already `active` subscription does not change a row, so it leaves no local trace beyond the thin webhook row.

Root linkage: checkout metadata or `client_reference_id` is `root_recording_id`; subscription metadata or the customer row supplies it later (`root_from`, `root_from_subscription`).

**Reuse:** webhook idempotency on `stripe_id`, subscription status including `"trialing"`, root linkage, and price `unit_amount` / `currency` as the value source when the invoice amount was not stored. Conversions does not read Stripe webhooks itself.

### Users identity and verification

Users at `401af0c`. `users` is a UUID primary key with `email` (unique), Devise `confirmed_at`, and `registered_with` limited to `password` or `otp` (`test/dummy/db/schema.rb`). OAuth rows are `recording_studio_user_identities`: unique `(provider, uid)` and unique `(user_id, provider)`, optional `email` (`app/models/recording_studio_user/identity.rb`). That identity is an OAuth login, not an advertising visitor.

`RecordingStudioUser::RegistrationCompleted::EVENT` is `"registration.completed.recording_studio_user"` (`lib/recording_studio_user/registration_completed.rb`). Payload is `user_id` and `method` (`:password`, `:oauth`, or `:otp`). Emission is inside `ActiveRecord.after_all_transactions_commit`. Call sites:

- password: `app/controllers/recording_studio_user/auth/registrations_controller.rb` `provision_password_account!`
- oauth: `lib/recording_studio_user/omniauth/identity_flow.rb`
- otp: `lib/recording_studio_user/services/complete_registration.rb`, after a separate in-process `"otp.registration_completed.recording_studio_user"`

Onboarding (`c8f66f9`, `lib/recording_studio_onboarding/users_registration_integration.rb`) subscribes to the unified event and reads only `payload[:user_id]` and `payload[:method]`. Extra keys would not change that subscriber. Renaming the event or removing those keys would.

Other notifications, all `otp.<event>.recording_studio_user`:

- issue: `lib/recording_studio_user/services/issue_otp.rb` (`challenge_id`, `user_id`, `purpose`)
- verified / failed: `lib/recording_studio_user/services/verify_otp.rb` (also `reason` on failure). `verified` is instrumented after the consume transaction returns
- email proof: `lib/recording_studio_user/services/complete_email_proof.rb` (`user_id`, `challenge_id`)

`record_profile!` (`lib/recording_studio_user/directory.rb`) writes a profile recording and bootstraps owner access. The profile recording id is not the user id. Registration payload does not include `root_recording_id`; onboarding creates the workspace after the event.

Password confirmation may set `confirmed_at` with `update_column` (`confirm_password_account!`). OTP confirmation uses Devise `confirm`. `confirmed_at` is the verified-email flag on `users`. There is no visitor cookie and no anonymous-to-user table.

**Reuse:** subscribe to `"registration.completed.recording_studio_user"` as the registration conversion source. Treat `users.id` as the stable user reference. Read `email` and `confirmed_at` from the user row at delivery time, under consent, rather than copying email onto the event. Use `recording_studio_user_identities` only as login provenance, not as attribution storage.

### Flatpack, Pages, Notifications

Flatpack (`530eb3e`) ships Stimulus controllers via `@hotwired/stimulus`. A later tracker should be a Stimulus controller loaded by an explicit host layout helper. No Flatpack change is required for that.

Pages (`9322768`) logs `"trashed"` through `log_event!` in `lib/recording_studio_pages/services/trash_recording.rb`. No page-view notification.

Notifications (`d7ce744`) instruments `"notify.recording_studio_notifications"` inside the create transaction (`lib/recording_studio_notifications/services/notify.rb`) and `"deliver.recording_studio_notifications"` in `DeliveryJob`. Those are delivery plumbing for product notifications. Conversions does not subscribe to them.

## 2. Missing contracts and events

Proposed names follow the Publishable and Users shape: `<fact>.<gem_namespace>`, emitted with `ActiveRecord.after_all_transactions_commit`, payload free of provider ids and of raw email. Canonical names on the right are what Conversions would subscribe as. Schema version starts at 1.

### Views — required, gem does not exist yet

Source name: `"recorded.recording_studio_views"`. Canonical: `"views.recorded"`.

The Views gem owns the decision that a view occurred (including once-per-visit if that is its rule). Payload:

| Field | Type | Notes |
|---|---|---|
| `schema_version` | integer | `1` |
| `event_id` | uuid | Views log row id. Stable source id. |
| `occurred_at` | time | |
| `recording_id` | uuid | Existing recording id. Omitted when the view is not a recording. |
| `recordable_type` | string | `"Page"`, press-kit recordable type, and so on. |
| `recordable_id` | uuid | Copied from the recording. Never a new id for that recordable. |
| `root_recording_id` | uuid | Nullable for pages outside a workspace. |
| `path` | string | Request path only. No query string, so click ids stay in the Conversions collector. |
| `classification` | string | Code-defined, for example `page`, `press_kit`, `recording`. |
| `visitor_id` | uuid | Optional. Present only if Views and Conversions share a first-party visitor id the host already issued. Otherwise omitted. |

Conversions must not count a Turbo navigation as another canonical view. Matching uses `event_id` as `source_event_id`.

### Stripe — required

Emit from `ProcessWebhook` after the database transaction commits, using the Stripe event id as `source_event_id`. A `:duplicate` webhook emits nothing. Suggested source names and canonical names:

| Source instrumentation | Canonical | When |
|---|---|---|
| `trial_started.recording_studio_stripe` | `stripe.trial_started` | Local status transitions to `trialing`, or a new row is created already `trialing`. |
| `subscription_activated.recording_studio_stripe` | `stripe.subscription_activated` | Status becomes `active` from anything else, including the `invoice.paid` past-due recovery. |
| `subscription_canceled.recording_studio_stripe` | `stripe.subscription_canceled` | `customer.subscription.deleted` handler. |
| `invoice_paid.recording_studio_stripe` | `stripe.invoice_paid` | Every non-duplicate `invoice.paid`, including invoices that do not change status. |
| `invoice_payment_failed.recording_studio_stripe` | `stripe.invoice_payment_failed` | Existing failure handler, after commit. |
| `allowance_purchased.recording_studio_stripe` | `stripe.allowance_purchased` | `ApplyAllowance` succeeds. Optional for the trial milestone. |

Shared payload:

- `schema_version` (1)
- `event_id` — Stripe event id (`evt_...`), which is already unique on `recording_studio_stripe_webhook_events.stripe_id`
- `occurred_at` — from the Stripe event `created` timestamp
- `root_recording_id`
- `subscription_id` — local `recording_studio_stripe_subscriptions.id` when one exists
- `stripe_subscription_id`
- `customer_id` — local customer UUID
- `status` — local status after the write
- `previous_status`
- `subscription_type`
- `price_id` — local price UUID

`invoice_paid` and `invoice_payment_failed` also include `invoice_id` (Stripe invoice id), `amount` (integer minor units), `currency`, and `first_payment` (boolean computed by Stripe from local history of accepted invoices, not by Conversions). Email stays on the customer row.

`trial_started` does not include a user id. The customer table has no user. Identity is resolved later through the acquisition-subject association.

### Users — mostly present

Existing `"registration.completed.recording_studio_user"` is the registration contract. Canonical subscription name: `"users.registered"`.

Additive fields that keep `user_id` and `method` intact, so Onboarding keeps working:

- `schema_version` (1)
- `occurred_at`
- `confirmed` — boolean from `confirmed_at`

No `email`. No `root_recording_id`, because the workspace may not exist until Onboarding runs. Linking the anonymous visitor happens in the registration request, where the visitor cookie is present, not from this payload alone.

No new verification event is required for the trial flow. `confirmed_at`, `"otp.email_proof_completed.recording_studio_user"`, and `"otp.verified.recording_studio_user"` stay Users concerns. Conversions treats `method: :otp` plus a confirmed user as verified. Password accounts can be confirmed in the same request (`confirm_password_account!`).

### Pages, Press kits, Publishable, Downloadable

No new event is required on Pages or Press kits for page views. Classification belongs on the Views payload (`recordable_type`, `classification`).

Publishable already emits `published.recording_studio_publishable`. A later "content published" conversion can subscribe to that existing event. No new name.

A download conversion would need a new after-commit event from Downloadable, for example `"downloaded.recording_studio_downloadable"` with `event_id` equal to the download-log id, `recording_id`, `root_recording_id`, `actor_id` nullable, `occurred_at`. Not part of the trial path. Downloadable's log is not a Logs registration today, so this event is a proposal for a later milestone only.

### Notifications

No conversion event. Product notification delivery is unrelated to advertising delivery.

### Canonical envelope inside Conversions

Normalize the payloads above into the instruction's envelope (`id`, `name`, `schema_version`, `occurred_at`, `source`, `source_event_id`, `root_recording_id`, `subject`, `actor`, `properties`). `actor` is the user when the source event has `user_id` or `actor_id`. `subject` is the subscription, invoice, or recording. Attribution subject is a separate resolved reference and is not copied from `actor`.

## 3. Sibling-gem changes (proposals only)

No gem other than this documentation in `RecordingStudio_conversions` is modified by this milestone. `RecordingStudio_attachable` and `RecordingStudio_library` are omitted on purpose.

### `RecordingStudio` (core)

No change required. Keep `"recordings.event_created"` inside `record!` as history. Do not add conversion knowledge. An optional later improvement is an after-commit variant of `instrument_event` for subscribers that cannot tolerate rollback. That would touch every current subscriber of `"recordings.event_created"`, including the dummy initializer, and is not needed if domain gems emit their own after-commit events.

### `RecordingStudio_views`

The repository has to stop being the gem template and become the page-view owner: collector, partitioned log registered through `RecordingStudioLogs.register`, and `"recorded.recording_studio_views"`. Conversions will not grow a parallel counter while that work is unfinished. This is the largest sibling proposal.

### `RecordingStudio_logs`

No change to the gem. Conversions and Views call `register` / `aggregate` / `delete_for_root`. Views is the producer of the page-view log. Conversions may register an aggregation against that log only for columns Views puts in `aggregatable`.

### `RecordingStudio_metrics`

No change. Conversions calls `RecordingStudioMetrics.register`. Logs' bridge already publishes eligible rollups.

### `RecordingStudio_admin`

No change. Conversions registers read-only screens when the gem is loaded.

### `RecordingStudio_accessible`

No change to the gem. Conversions may call `register_action` for `:"recording_studio_conversions.view_operations"` from its own engine. Admin role `:view` is enough if Marco accepts that.

### `RecordingStudio_stripe`

Required for the trial and payment milestones. After the webhook transaction commits, emit the events in section 2. Compare previous subscription status inside `ApplySubscription` so `trial_started` and `subscription_activated` are transitions. Emit `invoice_paid` for every newly stored `invoice.paid`, not only the `past_due` → `active` branch. Put `amount`, `currency`, and `first_payment` on that payload. Keep the unique `stripe_id` row as the durable source id. Do not add a dependency on Conversions. Do not put Meta field names in Stripe.

A replay helper that lists webhook rows by `event_type` and `processed_at` would let Conversions recover a missed notification without a second outbox. The stored JSON is too thin for that today (`event_payload`), so either the notification is the contract and must not be lost after commit, or the stored payload grows enough to rebuild it. Prefer the notification plus the existing unique row, and keep amount on the notification payload computed at handling time.

### `RecordingStudio_users`

No required behavior change. Optional additive keys on `"registration.completed.recording_studio_user"`: `schema_version`, `occurred_at`, `confirmed`. Leave `user_id` and `method` in place. Do not add email. Do not add a visitor id inside Users; the registration controller does not know advertising cookies, and Users must not depend on Conversions. The host or a Conversions Rack middleware associates the cookie during that request.

### `RecordingStudio_notifications`

No change.

### `RecordingStudio_pages`

No change. Views identifies a page by `recordable_type` and `recording_id`.

### `RecordingStudio_presskits`

No change for view counting. `presskits.kit_view_full` stays an access action. Views classifies a press-kit recording when it records the view. Do not emit a second view event from Press kits.

### `RecordingStudio_publishable`

No change. Existing `published.recording_studio_publishable` is available if a later rule needs it.

### `RecordingStudio_downloadable`

No change for the trial milestone. A download conversion later would add `"downloaded.recording_studio_downloadable"` after the download log commits. Not proposed as work in this milestone.

### `flatpack`

No change. The tracker is a Stimulus controller in the Conversions gem, following Flatpack's `@hotwired/stimulus` controllers. The host layout opts in.

### `RecordingStudio_onboarding`

No change. It already consumes registration completion. Conversions must tolerate the same event. Workspace creation still happens in the host provisioner, which is why acquisition identity is a host policy.

## 4. Proposed data model

All new tables live in the Conversions engine and use UUID primary keys (`gen_random_uuid()`), matching `recording_studio_recordings` (`db/install_migrate/20250101000001_create_recording_studio_recordings.rb`: `id: :uuid`, `recordable_id` uuid, `parent_recording_id`, `root_recording_id`). Recording ids and recordable ids are stored as references. The design has no migration that updates `recording_studio_recordings.id`, `recordable_id`, or `users.id`. Profile recordings created by `record_profile!` keep their ids. Stripe subscription UUIDs and `stripe_id` strings stay in Stripe's tables.

Visitors are not recordings and not recordables. Giving a visitor a row in `recording_studio_recordings` would mint a new recording id for something that is not a recordable and would tempt later remaps. The visitor id is its own UUID.

### `recording_studio_conversions_visitors`

| Column | Notes |
|---|---|
| `id` | UUID, the first-party anonymous visitor id. Set once, never updated. |
| `first_seen_at` | |
| `created_at` | |

Index: primary key only. No recording foreign key.

The id is issued by the server and stored in a first-party cookie. The browser cannot choose a user id.

### `recording_studio_conversions_attribution_observations`

One row per captured field. Historical rows are kept. There is no `fbclid` or `gclid` column.

| Column | Notes |
|---|---|
| `id` | UUID |
| `visitor_id` | UUID, not null |
| `root_recording_id` | UUID, nullable. Copied from the page's recording when known. |
| `provider` | Adapter key, for example `meta` |
| `field_name` | Declared by that adapter |
| `value` | Stored according to the field's sensitivity. Secrets never stored. |
| `source` | `query_parameter`, `cookie`, `request` |
| `captured_at` | |
| `expires_at` | |
| `consent_category` | |
| `consent_granted` | Boolean at capture time |

Indexes: `(visitor_id, captured_at)`, `(visitor_id, provider, field_name, captured_at)`, `(expires_at)`.

### `recording_studio_conversions_identity_links`

Anonymous visitor to verified user. Written when `"registration.completed.recording_studio_user"` is handled in a request that still has the visitor cookie, or when a later authenticated request presents the same cookie and the user is confirmed.

| Column | Notes |
|---|---|
| `id` | UUID |
| `visitor_id` | UUID, not null |
| `user_id` | UUID, not null. This is `users.id`, not a profile recording id. |
| `method` | `password`, `oauth`, or `otp` |
| `linked_at` | |
| `confirmed` | Copied from the user at link time |

Unique `(visitor_id, user_id)`. Index on `user_id`.

A second user on the same browser creates a second row. It does not rewrite the first. Resolution does not pick "the latest user" unless the host policy says so.

### `recording_studio_conversions_acquisition_subjects`

Host policy result for a workspace. Stripe events carry `root_recording_id` and no user.

| Column | Notes |
|---|---|
| `id` | UUID |
| `root_recording_id` | UUID, not null. Existing workspace recording id. |
| `subject_type` | `"User"` |
| `subject_id` | `users.id` |
| `policy` | Host policy name |
| `assigned_at` | |
| `superseded_at` | Null for the current row |

Unique partial index on `root_recording_id` where `superseded_at` is null. Replacing a policy inserts a new row and sets `superseded_at` on the old one. It does not update `subject_id` in place and does not touch the recording id.

If the resolver returns nothing, no row is written. The conversion stays unresolved and is visible as such. Another workspace member is not substituted.

### `recording_studio_conversions_occurrences`

Durable only after a rule matches, or when a match is suppressed for a reason operators must see (unresolved identity, consent withdrawn, missing required field). Unmatched page views do not get a row.

| Column | Notes |
|---|---|
| `id` | UUID. Logical conversion occurrence id. Stable across retries. |
| `rule_key` | Code-defined rule name |
| `source_event_name` | Canonical name |
| `source_event_id` | Views `event_id`, Stripe `evt_...`, or `users.id` for registration when the source has no separate event id |
| `source` | Gem namespace |
| `schema_version` | |
| `occurred_at` | |
| `root_recording_id` | Nullable UUID reference |
| `subject_type`, `subject_id` | Subscription, invoice, recording, or user |
| `actor_type`, `actor_id` | Who did it, when known |
| `attribution_subject_type`, `attribution_subject_id` | Host policy result. Nullable when unresolved. |
| `visitor_id` | Nullable |
| `properties` | Mapped, non-PII properties (`amount`, `currency`, `first_payment`) |
| `outcome` | `matched` or `suppressed` |
| `suppression_reason` | Nullable |

Unique `(rule_key, source_event_id)`. First-occurrence rules add a partial unique index on `(rule_key, attribution_subject_type, attribution_subject_id)` where `outcome = 'matched'`. That constraint is the business idempotency. Provider dedup ids are not.

Registration's source event has no id other than `user_id`. Use `user_id` as `source_event_id` for `"users.registered"` so a repeated notification cannot insert a second occurrence.

### `recording_studio_conversions_deliveries`

The outbox. Inserted in the same transaction as the occurrence. A job is enqueued after that transaction commits. A crash after commit leaves a `pending` row to be picked up.

| Column | Notes |
|---|---|
| `id` | UUID. Provider delivery id. |
| `occurrence_id` | UUID |
| `provider` | Adapter key |
| `channel` | `server` or `browser` |
| `status` | `pending`, `processing`, `accepted`, `retry_scheduled`, `permanently_failed`, `suppressed`, `expired` |
| `provider_dedup_id` | Stable derivation of the occurrence id. Not a new id per attempt. |
| `attempt_count` | |
| `next_attempt_at` | |
| `accepted_at` | Provider API acceptance, not advertising attribution |
| `terminal_reason` | Sanitized category |

Unique `(occurrence_id, provider, channel)`. Index `(status, next_attempt_at)`.

### `recording_studio_conversions_delivery_attempts`

Append-only. `delivery_id`, `attempted_at`, `outcome`, `error_category`. Index `(delivery_id, attempted_at)`.

### `recording_studio_conversions_consents`

`visitor_id`, nullable `user_id`, `category`, `granted`, `recorded_at`, `withdrawn_at`, `provenance` (json, no raw identifiers beyond the visitor and user ids). Index `(visitor_id, category, recorded_at)`.

Delivery jobs re-read the latest consent row before submit.

### What is not a table

Conversion rules, provider field declarations, and destination credentials stay in Ruby and environment variables. Admin reads the registry. High-volume collector errors and unmatched view counts go through Logs aggregations, not through `occurrences`.

### Identity flow the trial milestone needs

1. Visitor cookie id is `recording_studio_conversions_visitors.id`.
2. Declared Meta fields land in `attribution_observations` for that visitor.
3. Registration commits in Users and emits `"registration.completed.recording_studio_user"`.
4. The same request links `visitor_id` to `users.id` when the cookie is present and the account is confirmed.
5. The host resolver returns the acquisition user for the new workspace root and Conversions inserts `acquisition_subjects` for that `root_recording_id`.
6. A later Stripe `trial_started` carries `root_recording_id` only. Lookup is acquisition subject → user → identity links → observations. A missing link suppresses delivery with a reason. It does not attach another member of the workspace.

## 5. Provider adapter boundary

The core matcher, attribution store, identity link, and delivery outbox accept an adapter object. They do not branch on `:meta`, `:google`, or `:tiktok`.

An adapter, registered by key, answers:

- `attribution_fields` and `identity_fields` — name, source, required, alternatives, transform, consent category, sensitivity, retention, which canonical events they apply to
- `browser_module` — a Stimulus controller name or `nil`
- `delivery_channels` — subset of `server` and `browser`
- `event_name_for(rule)` — external name such as `StartTrial`
- `build_payload(occurrence, fields)` and `deliver(payload)`
- `normalize_error` — retryable or permanent
- `max_event_age`
- `dedup_id_for(occurrence)` — stable

The collector asks every enabled adapter for its fields and captures that set. Adding Google or TikTok is a new adapter class plus a `config.destination` entry. It does not change the visitors table, the observation columns, the matcher, the Views subscription, or the host layout helper. The layout helper prints `recording_studio_conversions_tags`; enabled browser modules are data on that tag.

Meta is the first adapter and owns Pixel formatting, Conversions API submission, hashing, and test-event mode. `accepted` means the API returned success. It does not mean Meta attributed the conversion.

Google (`gclid`, `gbraid`, `wbraid`) and TikTok stay unimplemented until their own milestone. Their field lists in the instruction are illustrative. Official docs get checked when those adapters are written. **Unverified** against current Meta, Google, and TikTok API docs in this milestone.

## 6. Milestone plan from M2 onward

M1 is this document.

**M2 — Event and conversion core.** Subscriptions, canonical envelope, code-defined rules, deterministic match, idempotency on `(rule_key, source_event_id)`. Subscribe to the existing Users registration event. Stripe and Views subscriptions are declared and skipped cleanly when the source event does not exist. No provider calls.

**M3 — Provider declarations.** Adapter registry and field, consent, channel, and age contracts. A fake adapter in tests. No Meta HTTP yet.

**M4 — Attribution and browser collection.** Visitor id, observation rows, Stimulus tracker, consent, server-side link from visitor to `users.id` on registration. Host `attribution_subject_resolver` and `acquisition_subjects`. Turbo-safe single initialization.

**M5 — Durable delivery.** Occurrences, deliveries, attempts, ActiveJob, backoff, consent re-check, Logs registration for diagnostics, Metrics counts. External HTTP still stubbed.

**M6 — Meta adapter.** Conversions API and Pixel behind the adapter interface. Shared dedup id. Test events. Hashing. Acceptance stored as `accepted`.

**M7 — First end-to-end trial.** Depends on the Stripe `trial_started` proposal landing in `RecordingStudio_stripe`. Path: Meta click id stored for a visitor → registration link → host acquisition subject for the workspace root → Stripe trial event → `StartTrial` rule → Conversions API. This is blocked until Stripe emits that event. Users registration can be integration-tested before Stripe is.

**M8 — Payment and deduplication.** Depends on Stripe `invoice_paid` with amount, currency, and `first_payment`. Browser receipts for dual-channel delivery. Receipts are server-issued and cannot assert a payment.

**M9 — Views and Admin.** Depends on Views existing and emitting `"recorded.recording_studio_views"`. Read-only Admin screens over the registries and delivery rows. Until Views ships, Admin can still show registration and Stripe activity.

**M10 — Second adapter test.** A mock adapter with a different required field. Proves Google or TikTok would be a new class. Not a production Google integration.

Sibling work that gates M7 and M9 is proposed in section 3. It is not part of this pull request.

## Key decisions

1. Domain events are ActiveSupport Notifications emitted after commit by the owning gem. Conversions only subscribes. `"recordings.event_created"` stays history and is not the conversion bus.
2. `"registration.completed.recording_studio_user"` is the registration source, with canonical name `users.registered`. Its `user_id` and `method` stay stable because Onboarding reads them.
3. Page views belong to a future Recording Studio Views gem. The Logs site-view guide is a dummy pattern to copy, not a collector that already exists. Conversions will not count views itself.
4. Stripe must emit `trial_started` and a true `invoice_paid` after the webhook transaction commits, keyed by the existing unique Stripe event id. Today's `invoice.paid` handler only repairs `past_due` subscriptions and drops amount and currency.
5. The acquisition user for a workspace is an explicit `acquisition_subjects` row chosen by the host. Stripe customers have no `user_id`, so a trial event cannot imply a user. A missing subject suppresses delivery.
6. Anonymous identity is a Conversions visitor UUID, linked to `users.id` when a confirmed registration shares that cookie. Recording ids, recordable ids, profile recording ids, and user ids are never rewritten or used as substitutes for each other.
7. Matched conversions and deliveries are durable Conversions tables. The delivery row is the outbox. Page views and other high-volume rows stay in Logs. Provider acceptance is status `accepted`, separate from attribution.
8. Provider behavior sits behind an adapter. Meta is the first implementation. Google and TikTok are additional adapters and do not change core tables or the shared tracker.

## Open questions for Marco

1. Confirm that Conversions has no need of `RecordingStudio_attachable` or `RecordingStudio_library`. None was found. If customer matching later needed an uploaded file or image byte, that would be a new question, and those gems would still not be edited from this repo.
2. Should Users add `schema_version`, `occurred_at`, and `confirmed` to `"registration.completed.recording_studio_user"`, or should Conversions read `confirmed_at` from the user row and timestamp the occurrence itself? Onboarding ignores unknown keys today (`c8f66f9`).
3. Who writes `acquisition_subjects`: a host lambda invoked by Conversions when it sees registration and the workspace already exists, or an explicit host call after Onboarding provisions the workspace? Registration currently fires before the workspace exists.
4. Is one current acquisition user per root recording the rule (partial unique index), or must several users stay eligible? The instruction says the host decides and that the system must not guess.
5. For `invoice_paid`, should `amount` be the Stripe invoice `amount_paid`, and should `first_payment` mean the first invoice Stripe marks paid for that local subscription? Stripe does not store either value today.
6. Should a trial that is created already `trialing` emit `trial_started` once, and should a later `invoice.paid` for the trial fee also be eligible as `stripe.invoice_paid`? Product metadata has a trial fee (`RecordingStudioStripe::Trial`).
7. Views does not exist. Should that gem be built in `RecordingStudio_views` (currently a template at `b57b35a`) before M9, and should its log be the Logs dummy `site_views` shape with `resource_type`, `root_recording_id`, and `recording_id`?
8. Should the first-party visitor id be new, or is there an existing anonymous device key to reuse? Dummy schemas in other repos contain `idx_rs_root_switchable_anonymous_device_scope`. `RecordingStudio_root_switchable` itself was not cloned. **Unverified** whether that device key is stable, first-party, and appropriate for advertising.
9. Admin access: is Accessible role `:view` on the admin recording enough, or do you want a dedicated action key `:"recording_studio_conversions.view_operations"`?
10. Webhook replay: if the process dies after the Stripe transaction commits and before `after_all_transactions_commit` runs, is rebuilding from `recording_studio_stripe_webhook_events` required? The stored payload cannot rebuild amount and currency today.
