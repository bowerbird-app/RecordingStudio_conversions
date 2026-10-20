# RecordingStudioConversions

Records provider-neutral conversion occurrences for Recording Studio.

## What's Included

- **Recording Studio** 4.x gem pinned and configured
- **Devise** authentication with a pre-seeded admin user
- **Workspace**, **Folder**, and **Page** recordables seeded into the dummy host app
- **FlatPack** UI component library for all views
- **Dummy app** (`test/dummy/`) with a FlatPack sign-in screen, a home page on Recording Studio's default layout, mounted Recording Studio routes, and FlatPack's built-in rounded theme

Authenticated dummy pages use Recording Studio's shared default layout (`RecordingStudio::UsesDefaultLayout`) plus FlatPack CSS and JS. Devise keeps its own sign-in layout. Dummy `/docs/*` pages stay in the dummy app as a host-app sandbox; they are not the product README.

## Quick Start

### Cursor Cloud Agent (Recommended)

A Cloud Agent boots this repo into a ready-to-use dev environment with no manual steps. The setup lives in `.cursor/`:

- `install.sh` provisions Ruby (pinned by `.ruby-version`), PostgreSQL 16, all gems, the seeded dummy database, and compiled CSS at build time, then fetches Recording Studio skills.
- `start.sh` starts PostgreSQL on every boot.
- `environment.json` runs the `rails-server` and `tailwind-watch` terminals and exposes port 3000.

Open port 3000 and sign in at `/users/sign_in`. No environment variables are required — the dummy app's `database.yml` defaults match the provisioned PostgreSQL cluster.

### GitHub Codespaces

1. Click **Code** → **Codespaces** → **Create codespace**
2. Wait for setup to complete
3. Run:
   ```bash
   cd test/dummy
   bin/rails db:setup
   bin/dev
   ```
4. Open port 3000 — you'll land on the dummy app home page and can sign in at `/users/sign_in`

The dummy app is intended as a host-app validation surface for authentication, FlatPack rendering, Tailwind source scanning, and Recording Studio route wiring.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

### Login Credentials

| Field    | Value             |
|----------|-------------------|
| Email    | admin@admin.com   |
| Password | Password          |

The login form is prefilled with these credentials for fast access.

### Useful Routes

- `/` — dummy app home page
- `/users/sign_in` — Devise sign-in page
- `/recording_studio` — redirect to `/` while the mounted Recording Studio engine remains data/API-focused
- `/docs/install`, `/docs/config`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, `/docs/methods` — dummy-only starter pages

The home page in `test/dummy/app/views/home/index.html.erb` is a starting point for a minimal demo of the gem's primary behavior. Keep deeper explanations on the dummy docs pages, not in this README.

## Architecture

### Root Recording Pattern

This template follows Recording Studio's root recording pattern:

- **Workspace** is the top-level recordable
- **Folder** and **Page** demonstrate nested recordables under the workspace root
- Each configured recordable declares `recording_studio_recordable(...)`; strict declaration validation stays enabled
- A root `RecordingStudio::Recording` wraps the Workspace
- `Current.actor` is set from `current_user` (Devise) in `ApplicationController`

### Extending Recording Studio

To add new recordable types:

1. Create your model (e.g., `Page`, `Comment`)
2. Register it in `config/initializers/recording_studio.rb`:
   ```ruby
   RecordingStudio.configure do |config|
     config.recordable_types = ["Workspace", "YourNewType"]
   end
   ```
3. Declare whether the model can be a root and which parents may contain it:
   ```ruby
   class YourNewType < ApplicationRecord
     recording_studio_recordable label: "Your new type",
                                 root: false,
                                 allowed_parent_types: ["Workspace", "Folder"]
   end
   ```
4. Validate declarations and create recordings under the root:
   ```ruby
   RecordingStudio.validate_recordable_declarations!
   root_recording = RecordingStudio.root_recording_for(workspace)
   root_recording.record(YourNewType) do |record|
     record.title = "Example"
   end
   ```

### Recordable Declarations

Every configured ActiveRecord recordable type must declare its hierarchy rules. Declarations are required; they are not version-specific.

- `Workspace` declares `root: true`
- `Folder` and `Page` declare `root: false, allowed_parent_types: ["Workspace", "Folder"]`
- `config.require_recordable_declarations = true` remains enabled in the dummy app initializer

Useful console checks:

```ruby
RecordingStudio.validate_recordable_declarations!
RecordingStudio.root_recordable_types
RecordingStudio.allowed_parent_types_for("Page")
```

### Capabilities

Capability mixins are opt-in. Installing this gem does not enable mixins on host types.

The dummy Workspace enables Accessible because that addon is bundled:

```ruby
RecordingStudio.enable_capability(:accessible, on: Workspace)
```

The template also ships one example mixin that uses core 4.2.0's `include_for` factory:

```ruby
include RecordingStudio::Capabilities::Example.to(label: "dummy workspace")
```

`.to` wraps `RecordingStudio::Capabilities.include_for`. It does not add a fourth verb and it does not call `enable_capability` / `set_capability_options` itself. Folder and Page stay without the example mixin.

Use core `RecordingStudio::Hooks` and `RecordingStudio::Services::BaseService`. Do not copy those classes into a new addon.

### FlatPack UI Components

All views use FlatPack ViewComponents. Available components include:

- `FlatPack::Button::Component` — Buttons (`:primary`, `:secondary`, `:ghost`)
- `FlatPack::Card::Component` — Cards (`:default`, `:elevated`, `:outlined`)
- `FlatPack::Alert::Component` — Alerts (`:success`, `:error`, `:warning`, `:info`)
- `FlatPack::Badge::Component` — Status badges
- `FlatPack::Table::Component` — Data tables
- `FlatPack::TextInput::Component`, `EmailInput`, `PasswordInput` — Form inputs
- `FlatPack::PageNav::Component` — Default-layout page navigation
- `FlatPack::PageTitle::Component` — Page titles

Use the live FlatPack demo app at [flatpack.bowerbird.io](https://flatpack.bowerbird.io/) as the approved UI reference for current shared patterns. Its component table is the fastest way to discover available FlatPack components before introducing new custom UI.

See the [FlatPack README](https://github.com/bowerbird-app/flatpack) for full documentation.

## Conversions (milestone 2)

This gem records provider-neutral conversion occurrences. It requires PostgreSQL. The occurrence table uses `jsonb` and partial unique indexes, which SQLite and MySQL do not provide.

The host confirms users with Devise `:confirmable`. A host that does not load RecordingStudio_users needs these four columns on the user table: `confirmation_token`, `confirmed_at`, `confirmation_sent_at`, and `unconfirmed_email`. `bin/rails generate recording_studio_user:migrations` copies them from `add_devise_confirmable_to_users`. `confirmed?` alone is not enough: the `confirmed_at` column must exist. `config.user_class_name` defaults to `"User"`. That setting is used only when RecordingStudio_users is not loaded. When it is loaded, `RecordingStudioUser.config.user_class_name` wins, and a different value here warns at boot. A name that does not resolve warns at boot, and raises when `eager_load` is on:

```ruby
RecordingStudioConversions.configure do |config|
  config.user_class_name = "User"
  config.raise_errors = false
end
```

`raise_errors` stays false in production. A matcher failure instruments `failed.recording_studio_conversions` and logs. It does not raise into the producer. Set `raise_errors` in test when a failure should surface.

Rules are Ruby. Stripe `invoice_paid` has no `trial_fee` key. Match `first_payment` instead. Stripe `customer_id` is not stored. `config.excluded_subscription_statuses` defaults to `%w[canceled]`: a paid invoice on a canceled subscription is not a conversion. That list is policy, not a Stripe rule, and a host can replace it. `incomplete_expired` and `unpaid` are not excluded unless added. A missing or blank `subscription_status` or `billing_reason` is unknown and does not change the match. Source ids and user ids must be UUID strings. Any other value is unusable and the event is skipped:

```ruby
RecordingStudioConversions.configure do |config|
  config.conversion :start_trial do
    source "stripe.trial_started"
    first_occurrence!
  end

  config.conversion :purchase do
    source "stripe.invoice_paid"
    condition :first_payment, equals: true
  end

  config.conversion :pricing_view do
    source "views.recorded"
    recording pricing_recording_id
  end
end
```

Subscriptions, and the payload key used as `source_event_id`:

| Notification | Canonical name | Id key |
|---|---|---|
| `registration.completed.recording_studio_user` | `users.registered` | `user_id` |
| `trial_started.recording_studio_stripe` | `stripe.trial_started` | `id` |
| `invoice_paid.recording_studio_stripe` | `stripe.invoice_paid` | `id` |
| `page_view.recorded.recording_studio_views` | `views.recorded` | `page_view_id` |

After Onboarding creates the workspace, the host records the one acquisition user. A later call replaces that user and does not keep the previous one. A rooted first-occurrence rule still matches only once for that root. On `views.recorded`, `first_occurrence!` dedupes per root, not per viewer:

```ruby
RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: user.id)
```

Suppressed rows (`unconfirmed_user`, `unknown_user`, `unresolved_acquisition_subject`, `already_recorded`) can be judged again after the host fixes the cause:

```ruby
RecordingStudioConversions.reevaluate!
```

A repeated notification for the same source id updates only a suppressed row. A matched row stays matched. Page-view `visitor_id` is taken from the payload, and the conversion is attributed to that view's `user_id`. Other events fall back to Root Switchable's device key. This gem does not set a cookie.

## Providers (milestone 3)

Provider contracts are named classes that the host's main Zeitwerk loader will not unload. Registration calls `Rails.autoloaders.main.unloadable_cpath?` when that method exists and Rails is loaded, and skips the check when it does not. An adapter is a gem class, a file required from the initializer, or `autoload_lib_once`.

The reload check runs only when reloading is on. An adapter under `app/` raises in development and passes in test and production, where Zeitwerk does not unload constants. Rails 8.1 `config.autoload_lib` adds `lib` to the reloadable autoloader, so a class autoloaded from there is rejected in development too. A file in that managed `lib/` that is required before Zeitwerk setup is accepted and survives reload. An initializer runs before setup, which is why requiring the file there works. An anonymous class is rejected. Registering the same key with the same class object again does nothing. A different class for that key raises `already registered`.

The registry starts empty, and the app boots with no destination. A destination enables an adapter. Option values such as an access token stay on the destination. `inspect`, `to_s`, and `pretty_print` on the destination and the configuration print option keys only. `to_h` omits option values. `deconstruct`, `deconstruct_keys`, and `Marshal.dump` carry the raw options, so never cache, log, or serialize a destination. `Destination.new(**destination.to_h, options: destination.options)` round-trips, with the options passed back in by the caller.

```ruby
# lib/example_adapter.rb — required below, not autoloaded
class ExampleAdapter < RecordingStudioConversions::Adapters::Base
  key :example
  consent category: :advertising, collection: true, delivery: true
  delivery_channels :server
  conversion_event :purchase, as: "Purchase"
  conversion_event :first_purchase, as: "Subscribe"
end

RecordingStudioConversions.configure do |config|
  require Rails.root.join("lib/example_adapter")
  config.register_adapter :example, ExampleAdapter
  config.conversion :purchase do
    source "stripe.invoice_paid"
  end
  config.conversion :first_purchase do
    source "stripe.invoice_paid"
  end
  config.destination :example, adapter: :example, access_token: ENV.fetch("EXAMPLE_ACCESS_TOKEN")
end
```

`conversion_event` maps a conversion rule key (`Rule#key`), not the source event name. `purchase` and `first_purchase` can share a source and still name different provider events. `event_name_for` reads that rule key. `register` and `configure` do not check those keys, so the adapter may be registered before its rule in the same block or in a later initializer. `RecordingStudioConversions.check!` runs once from the engine's `config.after_initialize`, after every initializer. Inside `check!`, the source check always raises. The rule-key check follows `eager_load` and `raise_errors`: it raises when `config.raise_errors` is true or when `Rails.application.config.eager_load` is on. `raise_errors` defaults to `false` and can only escalate a warning to a raise; it does not suppress the eager-load raise. Otherwise `Rails.logger.warn` carries that same message, prefixed with `[RecordingStudioConversions]`. Production rake tasks run with `rake_eager_load` false (Rails 6.1+), so `db:migrate` and `assets:precompile` only warn, and only a server boot raises. Set `config.eager_load = ENV["CI"].present?` in the host test environment so CI catches a missing rule. A missing rule silently drops that conversion, because the processor only iterates configured rules, so the boot warning is the only signal. `config.raise_errors` also re-raises event-processing errors at runtime, so setting it true for a strict boot check changes runtime error handling too. Field `events` and `required_for` must be configured source names (subscription canonical names, or a rule `source`) when those sources exist. That source check still runs at registration.

Attribution and identity fields declare source, required or optional, alternatives, a transform name, consent category, sensitivity, and retention. Every alternative must name another declared field. `transform` is stored and not called.

`sufficient?(available, event_name:, channel: nil)` answers from those declarations. `channel: nil` applies every channel's requirements together, so a server-only required field still counts.

`within_age?` accepts a `Time`, `DateTime`, or `ActiveSupport::TimeWithZone`. A `Date` raises `ArgumentError`. `nil` and `String` are not within age, including when the adapter sets no max age. A timestamp more than 5 minutes ahead of now is not within age. That window is clock skew (`Adapters::Queries::FUTURE_CLOCK_SKEW`).

`build_payload`, `deliver`, `normalize_error`, and `dedup_id_for` are instance methods and raise `NotImplementedError`. Construct an adapter with `initialize(destination:)` so delivery can read that destination's options. This milestone does not deliver fields or call a provider.

## Attribution and browser collection (milestone 4)

The host opts into the shared tracker in a layout. It is not added to every Recording Studio page. The layout also needs `csrf_meta_tags`. The helper emits one plain script. It is not a Stimulus controller: the host does not register a controller, and a new provider does not edit the layout. The script listens for `DOMContentLoaded` and `turbo:load`, which is the Turbo lifecycle this collector needs. A later consent grant sends only fields that have not already been posted for that URL. Fields already collected for the URL stay on the page and are not posted again.

```erb
<head>
  <%= recording_studio_conversions_tags %>
</head>
```

Mount the engine so the tracker can post to `/recording_studio_conversions/collection` and `/recording_studio_conversions/consent`. Those two POSTs use Rails `rate_limit` (60 requests per minute per IP) and keep `protect_from_forgery`. The limit is counted in the host cache (`config.cache_store`). `:null_store`, the Rails test default, does not count, so the host needs a real store such as `:memory_store` or Redis before the limit applies. With no destination configured, the tag renders and collects nothing.

The visitor id is Root Switchable's device key. This gem reads `Current.device_key`, or the existing encrypted cookie when an engine request has not run Root Switchable's `before_action`. The cookie is decrypted on a detached jar, so a key rotation does not write `Set-Cookie`. It does not call `DeviceKey.fetch` and it does not set a cookie.

A signed-in collection or consent request calls `RecordingStudio.configuration.actor` with the engine controller, the same way Recording Studio Views calls its actor resolver. A zero-argument lambda still runs and does not receive that controller. The stock default is `-> { Current.actor }`. Recording Studio Users does not set `Current.actor`. This engine does not run the host `ApplicationController`, so a `before_action` that assigns `Current.actor` there never runs on these routes, and the signed-in user is nil. Give the lambda the controller:

```ruby
RecordingStudio.configure do |config|
  config.actor = lambda do |controller = nil|
    actor = Current.actor
    if actor.nil? && !controller.nil? && controller.respond_to?(:current_user)
      actor = controller.current_user
    end
    actor
  end
end
```

The optional argument keeps other Recording Studio callers, which invoke the lambda with no arguments, working. The dummy app uses this lambda. `current_user` is on the engine controller because Devise includes its helpers in `ActionController::Base`. This gem does not read Warden.

Collection stores one row per permitted field on `recording_studio_conversions_attribution_observations`. Rows are historical. A later click does not replace an earlier one. There is no column per advertising provider. Personal-sensitivity fields are not stored. An IP address is personal on every adapter and is never stored, even when a field declares it as an identifier. Undeclared query parameters and cookies are ignored. A browser body cannot create a conversion occurrence, choose the visitor id, or supply a receipt. `BrowserReceipt.issue` and `dedup_id_for` still raise `NotImplementedError`.

Consent is fail-closed. `RecordingStudioConversions.record_consent!` records a category for a visitor. Omitted provenance is `{ "source" => "host" }`. The browser endpoint always records `source` `browser` and ignores a client-supplied source. Unknown sources are rejected. `granted` must be the literal `true` or `false`. The category must be one the configured adapters declare. Collection and later resolution both read the latest row. Withdrawal keeps the observation and stops it from being selected. Provider module scripts are served only after that category is granted. A module URL is `403` until then and `200` after, which is itself a consent signal. Responses send `Cache-Control: private` and `Vary: Cookie` so one visitor's script is not reused for another. Log filtering redacts parameter keys `value` and `visitor_id` only, not names such as `default_value`.

A confirmed registration links the device key to `users.id` on `recording_studio_conversions_identity_links` (`auth_method` is `password`, `oauth`, `otp`, or null). A second confirmed user on the same key inserts another row. The first pair is left as it was. An unconfirmed registration waits until `reevaluate!` sees `confirmed_at`. A signed-in collection request writes that link even when advertising consent is absent. Observations still require an explicit grant.

The default attribution resolver reads the one acquisition user the host recorded for that root. Set `config.attribution_subject_resolver` to replace that policy. A return value that is not that recorded user is `ambiguous_acquisition_subject`. The occurrence does not switch to another member. A missing row stays `unresolved_acquisition_subject`. `RecordingStudioConversions.attribution_for(root_recording_id:)` returns the subject and the unexpired observations linked through that user. Observations stamped with a different root are left out. A null root, captured before a workspace existed, is eligible.

`delete_attribution_for_user!` removes that user's links and that user's consent grants. A withdrawal is kept: its `user_id` is cleared before the rest of that user's consent rows are deleted, so an earlier anonymous grant does not become the latest row again. Observations and anonymous consent on a device key stay while another user is still linked to that key. Those observations, including ones captured while the deleted user was the signed-in visitor, stay resolvable for the remaining linked user when the latest consent for that device is still a grant. `delete_attribution_for_root!` removes observations stamped with that root.

## Tech Stack

| Component       | Version |
|-----------------|---------|
| Ruby            | 3.3+    |
| Rails           | 8.1+    |
| PostgreSQL      | 16      |
| TailwindCSS     | 4       |
| RecordingStudio | 4.x (`~> 4.2` in the gemspec; dummy GitHub tag `v4.7.0`) |
| Accessible      | dummy GitHub tag `v0.18.0` |
| Trashable       | dummy GitHub tag `v0.11.0` (`require: false`; query-only via Accessible) |
| Root Switchable | dummy GitHub tag `v0.9.0` |
| FlatPack        | dummy GitHub tag `v0.1.196` |
| Devise          | latest  |

The dummy Gemfile keeps `github:` sources so Bundler can fetch those gems. The gemspec still pins `recording_studio` to `~> 4.2` so copied addons declare the core dependency even when GitHub is the fetch source.

## Documentation

The original gem template documentation is preserved in `docs/gem_template/` as architectural reference material. Use it as background on the engine conventions; this README and the dummy app are the source of truth for the Recording Studio addon workflow.
