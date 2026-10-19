# AI Instruction: Build Recording Studio Conversions

**Repository:** `bowerbird-app/RecordingStudio_conversions`  
**Gem:** `recording_studio_conversions`  
**Ruby namespace:** `RecordingStudioConversions`

## 1. Objective

Build a reusable, production-quality Recording Studio gem for tracking conversions across advertising platforms.

The gem will:

- Subscribe to provider-neutral events emitted by existing Recording Studio gems.
- Collect advertising attribution identifiers through a shared browser integration.
- Associate anonymous visitor attribution with verified user identities.
- Resolve attribution for events that occur later, including Stripe subscriptions and payments.
- Match domain events against code-defined conversion rules.
- Deliver conversions through provider-specific browser and server adapters.
- Record conversion activity and delivery outcomes.
- Expose read-only operational monitoring through Recording Studio Admin.

Meta Ads will be the first implemented advertising provider.

The architecture must support future providers such as Google Ads and TikTok without modifications to the core conversion engine, attribution storage or shared browser tracker.

**This must be a reusable Recording Studio building block, not a Meta-specific integration.**

### Non-negotiable architectural decisions

1. Domain events are owned and emitted independently by the gems responsible for their business logic.
2. Domain gems must not depend on Recording Studio Conversions.
3. Recording Studio Views owns page-view collection and emits page-view events.
4. Conversions consumes Views events but does not implement a parallel page-view counting system.
5. Conversion definitions and mappings are configured in Ruby, not through Admin CRUD.
6. Each advertising provider declares its own attribution, identity and delivery requirements.
7. The shared browser tracker remains provider-agnostic.
8. The host application explicitly determines the attribution subject for conversions involving workspaces or multiple users.
9. Operational logging uses Recording Studio Logs.
10. Reporting uses Recording Studio Metrics.
11. Administration uses Recording Studio Admin and is read-only.
12. Important conversion deliveries must survive process crashes, retries and provider outages.
13. Privacy, consent, retention and root isolation must be enforced across collection, storage and delivery.

---

# 2. Inspect existing Recording Studio gems

Before implementing anything, inspect the actual source code and current public APIs of:

- `RecordingStudio`
- `RecordingStudio_views`, if available
- `RecordingStudio_logs`
- `RecordingStudio_metrics`
- `RecordingStudio_admin`
- `RecordingStudio_accessible`
- `RecordingStudio_notifications`
- `RecordingStudio_stripe`
- `RecordingStudio_pages`, if available
- `RecordingStudio_presskits`
- `flat_pack`

Inspect related browser tracking, authentication and session implementations in existing applications where accessible.

Establish:

- Which domain events already exist.
- How those events are emitted.
- Whether transactional event publication is supported.
- How Recording Studio Views captures and identifies views.
- How Logs registers log producers and aggregations.
- How Metrics discovers metric definitions.
- How Admin registers screens and navigation.
- How root ownership and authorization are resolved.
- How Rails layouts, Turbo and Stimulus are integrated.
- How background jobs and idempotency are implemented.

Do not create parallel frameworks when existing Recording Studio infrastructure already solves the problem.

If Recording Studio Views does not yet exist or lacks the required event contract, document that dependency and propose the necessary interface. Do not silently move its responsibilities into Conversions.

Before coding, produce a concise architecture assessment identifying reusable mechanisms, missing contracts, required sibling-gem changes and the proposed data model.

---

# 3. Architectural boundaries

The system must separate the following responsibilities.

| Component | Owner | Responsibility |
|---|---|---|
| Recording lifecycle | Core | Recordings and history |
| Domain lifecycle events | Domain gems | Registration, trial, payment, publish, download |
| Page views | Views | Page/resource view collection and events |
| Attribution capture | Conversions | Provider-declared advertising identifiers |
| Identity resolution | Conversions + host | Associate conversions with the correct acquisition identity |
| Conversion matching | Conversions | Determine which events qualify for advertising tracking |
| Provider adapters | Conversions adapters | Provider declarations, payloads and delivery |
| Operational logging | Logs | Retention, partitions and aggregation |
| Reporting | Metrics | Reusable measurements |
| Administration | Admin | Read-only visibility |

The primary flow is:

```text
DOMAIN GEMS / RECORDING STUDIO VIEWS
                  |
                  | Provider-neutral events
                  v
       CONVERSIONS EVENT SUBSCRIBER
                  |
                  v
        CANONICAL EVENT ENVELOPE
                  |
                  v
         CONVERSION RULE MATCHING
                  |
                  v
        ATTRIBUTION SUBJECT LOOKUP
                  |
                  v
           ATTRIBUTION STORE
                  |
                  v
       PROVIDER REQUIREMENT RESOLUTION
                  |
                  v
           DURABLE DELIVERY
                  |
          +-------+-------+
          |               |
          v               v
     Browser Pixel    Server API
          |               |
          +-------+-------+
                  |
                  v
          LOGS AND METRICS
                  |
                  v
       RECORDING STUDIO ADMIN
```

The browser attribution collector runs independently of domain events, collecting only permitted information required by enabled providers.

Collection, conversion matching and provider delivery are distinct stages.

---

# 4. Independent domain event instrumentation

Domain gems must emit their own meaningful, provider-neutral events.

Do not require them to call:

```ruby
RecordingStudioConversions.register(...)
```

That would make domain gems dependent on Conversions.

Instead, use established instrumentation patterns, preferably ActiveSupport Notifications where compatible.

For example, Recording Studio Stripe might emit:

```ruby
ActiveSupport::Notifications.instrument(
  "trial_started.recording_studio_stripe",
  event_id: subscription.id,
  root_recording_id: root.id,
  subscription_id: subscription.id,
  customer_id: customer.id
)
```

This is an illustrative contract, not necessarily an existing event.

Recording Studio Conversions subscribes:

```ruby
RecordingStudioConversions.subscribe(
  "trial_started.recording_studio_stripe",
  as: "stripe.trial_started"
)
```

The subscription belongs to Conversions configuration or a dedicated integration initializer.

The event-producing gem must continue operating normally without Conversions installed.

## Event contracts

Each subscribed event should have:

- Canonical name.
- Source gem.
- Human-readable label and description.
- Source instrumentation name.
- Stable source event ID.
- Occurrence timestamp.
- Schema version.
- Declared properties.
- Subject reference.
- Actor reference where available.
- Root recording ID where applicable.

Support boot-time validation and discoverability.

Avoid subscribing indiscriminately to all Recording Studio history events.

## Transaction safety

Events representing completed business actions must not be emitted before the associated database transaction commits.

For financially significant events, investigate whether a transactional outbox is necessary to guarantee that an event is not lost between commit and publication.

Webhooks and service retries must not generate duplicate logical conversions.

The exact event integration must follow the owning gem's lifecycle semantics.

---

# 5. Recording Studio Views integration

**Recording Studio Views is the owner of page-view collection.**

Conversions must consume view events rather than implementing its own independent page-view counting infrastructure.

The Views gem should emit sufficiently structured events to distinguish:

- A general page view.
- A specific page.
- A particular recording.
- A press kit view.
- A view within a particular root.
- A route or page classification.

Illustrative event:

```ruby
{
  event_id: "view-uuid",
  event: "views.recorded",
  occurred_at: Time.current,
  recording_id: "recording-uuid",
  recording_type: "Page",
  root_recording_id: "root-uuid",
  path: "/pricing"
}
```

The exact schema must be coordinated with the Views gem.

Conversions must not redefine view semantics.

If Views counts a view once per qualified visit, Conversions should not independently count every JavaScript navigation as another canonical view.

## Browser coordination

The Conversions browser tracker may share browser lifecycle hooks with Views, but must not create a second competing page-view event source.

Investigate whether a shared bootstrap or browser identity mechanism is appropriate.

Avoid circular dependencies.

A page-view conversion should use the Views event ID as its source identity.

Do not automatically send every view to an advertising provider. Only code-defined conversion rules should enable external delivery.

---

# 6. Canonical event envelope

Normalize incoming events into a consistent format.

Illustrative representation:

```ruby
{
  id: "event-uuid",
  name: "stripe.invoice_paid",
  schema_version: 1,
  occurred_at: Time.current,

  source: "recording_studio_stripe",
  source_event_id: "stripe-invoice-id",

  root_recording_id: "root-uuid",

  subject: {
    type: "Invoice",
    id: "invoice-uuid"
  },

  actor: {
    type: "User",
    id: "user-uuid"
  },

  properties: {
    amount: 49.00,
    currency: "USD",
    first_payment: true
  }
}
```

Distinguish:

- Actor: who performed the action.
- Subject: the resource involved.
- Root: the workspace ownership boundary.
- Attribution subject: whose advertising acquisition context should be used.

These are not interchangeable.

Do not assume the latest active workspace member or workspace owner is the correct acquisition identity.

Schemas should be versioned and validated.

The canonical event envelope should not contain unnecessary personal information or provider-specific identifiers.

---

# 7. Event persistence strategy

Do not create a durable conversion record for every observed event.

Distinguish between:

**High-volume observations**

Examples: page views, resource views and browser interactions.

These should use their owning gem's logging infrastructure, Recording Studio Logs aggregation and configurable retention.

**Matched conversions**

Examples: a qualifying registration, trial or purchase.

These require a durable conversion occurrence and associated delivery obligations.

An unmatched page view should not necessarily generate a permanent conversion record.

The event registry and Admin should still be able to report aggregate activity from the originating gem.

## Event inspection

Where possible, support correlation between the source event and any matched conversion without duplicating the complete source event payload.

Define which diagnostic data must be retained to show why conversion matching succeeded or failed.

For high-volume events, use bounded diagnostic sampling or aggregated unmatched counts where appropriate.

Do not create an unbounded stream of detailed records simply to power an Admin screen.

---

# 8. Code-defined conversion rules

All conversion mappings must be defined in Ruby.

Illustrative configuration:

```ruby
RecordingStudioConversions.configure do |config|
  config.destination :meta,
    adapter: :meta,
    pixel_id: ENV["META_PIXEL_ID"],
    access_token: ENV["META_ACCESS_TOKEN"]

  config.conversion :registration do
    source "users.registered"
    destination :meta
    event_name "CompleteRegistration"
  end

  config.conversion :trial do
    source "stripe.trial_started"
    destination :meta
    event_name "StartTrial"
  end

  config.conversion :purchase do
    source "stripe.invoice_paid"
    destination :meta
    event_name "Purchase"

    condition :first_payment, equals: true

    property :value, from: :amount
    property :currency, from: :currency
  end
end
```

The final DSL should follow existing Recording Studio conventions.

Support:

- Multiple conversion rules per source event.
- Multiple destinations.
- Conditions on declared event properties.
- Root and recording filters.
- Property mappings.
- Values and currencies.
- First-occurrence rules.
- Code-defined enable/disable settings.
- Delivery method selection.

Conversion rules must not need to repeat the provider's attribution and identity field requirements.

Those requirements belong to the provider adapter.

## Conversion identity

Each logical conversion occurrence must have a stable identifier.

Distinguish:

1. Source event ID.
2. Logical conversion occurrence ID.
3. Provider delivery ID.
4. Provider-specific deduplication ID.

A single source event may produce multiple logical conversions or deliveries.

Ids must remain stable across retries.

A first-occurrence rule must be enforced through a business-level uniqueness constraint, not merely by reusing a browser deduplication ID.

---

# 9. Explicit acquisition identity

**The host application must explicitly determine the attribution subject for conversions.**

This is particularly important when a workspace has multiple users.

Consider:

- User A registers the workspace.
- User B activates a trial.
- User C manages billing.
- Stripe later confirms a payment.

The system must not guess whose acquisition attribution applies.

## Host attribution policy

Provide an explicit host-configurable policy for selecting the conversion attribution subject.

For example:

```ruby
RecordingStudioConversions.configure do |config|
  config.attribution_subject_resolver = lambda do |event|
    FeaturedIn::AcquisitionIdentity.resolve(event)
  end
end
```

This is an illustrative API.

The resolver should return a stable, validated reference to the selected acquisition identity.

The host may preserve the original registering user's acquisition identity for the workspace, or use another documented policy.

This decision belongs to the host, not to the advertising adapter.

## Persisting the association

Where appropriate, persist an explicit acquisition identity association when the customer or workspace is created.

Later Stripe events can resolve that association even when the original user is no longer signed in.

Do not silently substitute another user if the selected attribution subject cannot be resolved.

Make unresolved or ambiguous identity visible in operational diagnostics.

Support verified mappings between visitors, users, workspaces, customers and subscriptions.

Root boundaries must be enforced.

---

# 10. Provider adapter architecture

Each advertising provider must register an adapter implementing a common contract.

The adapter owns:

- Provider capabilities.
- Attribution requirements.
- Identity requirements.
- Browser integration requirements.
- Supported conversion events.
- Validation and transformations.
- Payload construction.
- External delivery.
- Error normalization.
- Retryability.
- Deduplication behavior.
- Provider-specific submission deadlines.

The shared conversion engine must not contain conditions such as:

```ruby
if provider == :meta
  # ...
end
```

Use adapter capabilities and standardized interfaces instead.

Meta is the first concrete implementation.

Google Ads and TikTok should be possible without modifying the core architecture.

---

# 11. Provider-defined field requirements

Each provider must declare the attribution and identity information it needs.

The core must not contain a predefined list of advertising identifiers.

## Example Meta declaration

```ruby
class MetaAdapter < BaseAdapter
  attribution do
    field :fbclid,
      source: :query_parameter,
      required: false

    field :fbp,
      source: :cookie,
      required: false

    field :fbc,
      source: :cookie,
      required: false
  end

  identity do
    field :email,
      source: :user,
      required: false,
      transform: :meta_email_hash

    field :ip_address,
      source: :request,
      required: false

    field :user_agent,
      source: :request,
      required: false
  end
end
```

## Example Google declaration

```ruby
class GoogleAdsAdapter < BaseAdapter
  attribution do
    field :gclid,
      source: :query_parameter,
      required: false

    field :gbraid,
      source: :query_parameter,
      required: false

    field :wbraid,
      source: :query_parameter,
      required: false
  end
end
```

These are illustrative interfaces. Validate actual provider requirements using current official documentation when implementing each adapter.

## Field capabilities

Declarations must support:

- Name and type.
- Collection source.
- Required or optional status.
- Conditional requirements.
- Alternative acceptable identifiers.
- Normalization and transformation.
- Capture timing.
- Persistence and retention.
- Consent category.
- Sensitivity classification.
- Supported conversion types.
- Supported delivery methods.

For example, a field may be required for one provider event type but optional for another.

The adapter should determine whether the available information is sufficient for a particular delivery.

Missing optional identifiers must not prevent an otherwise valid conversion.

---

# 12. Browser tracking integration

Implement one shared, provider-agnostic browser tracker.

The host application explicitly opts into tracking through its Rails layout.

Illustrative usage:

```erb
<head>
  <%= recording_studio_conversions_tags %>
</head>
```

Follow existing Recording Studio and Flatpack conventions.

The helper should:

- Load the shared tracker.
- Supply permitted public configuration.
- Initialize consent-aware collection.
- Load enabled provider browser modules when permitted.
- Avoid exposing server credentials.
- Support Turbo and Stimulus lifecycle requirements.

Tracking must not be injected automatically into every Recording Studio page.

The host determines which layouts enable tracking.

## Shared tracker responsibilities

The tracker should:

- Resolve a first-party anonymous visitor/session identifier when permitted.
- Collect provider-declared query parameters.
- Read permitted provider-declared cookies.
- Communicate with the backend collector.
- Coordinate consent state.
- Link browser activity with authenticated sessions through secure server-side flows.
- Dispatch configured browser conversions.
- Avoid duplicate initialization.
- Handle navigation and browser lifecycle changes.

The shared tracker must contain no provider-specific pixel logic.

## Provider browser modules

Each adapter may register a browser module.

The provider module owns:

- Browser SDK or pixel initialization.
- Provider-specific browser identifiers.
- Provider event formatting.
- Browser delivery.
- Provider-specific deduplication parameters.

Loading an additional provider must not require editing the host layout or shared tracker.

## Views integration

Recording Studio Views owns canonical page-view observation.

The Conversions tracker must not duplicate its page-view collector.

Coordinate browser lifecycle and visitor context where useful.

Only deliver a page-view event externally when a configured conversion rule requires it.

---

# 13. Browser and server event coordination

The gem must support browser-only, server-only and dual-channel conversion delivery.

## Browser-only delivery

Examples may include selected frontend interactions or eligible page views.

## Server-only delivery

Examples include confirmed payments or events that occur without an active browser.

## Dual-channel delivery

Some conversions may be sent through both a browser pixel and server API.

For these, both channels must use a shared canonical conversion occurrence ID or a provider-defined stable derivation of it.

For example, after a successful registration:

1. The server commits registration.
2. A canonical conversion occurrence is established.
3. The server queues an eligible API delivery.
4. The browser receives an authorized conversion receipt containing a public event identifier.
5. The browser module sends the corresponding pixel event if allowed.

The browser must not independently generate a competing conversion ID for the same action.

## Browser delivery security

The browser must not be able to invent an arbitrary successful payment or trial event.

Only trusted server-issued conversion receipts may trigger browser delivery of server-authoritative conversions.

Use short-lived, scoped, non-sensitive receipts with appropriate integrity protections.

Provider browser calls may not offer reliable delivery acknowledgement.

Do not claim a browser event succeeded merely because JavaScript invoked the provider SDK.

---

# 14. Attribution collection and storage

Collection must be separate from conversion delivery.

A visitor arriving from an advertisement may create an attribution observation without triggering an advertising conversion.

The shared collector only captures declared, permitted fields for enabled providers.

## Collection sources

Support a controlled catalog including:

- Query parameters.
- Cookies.
- Request context.
- Session context.
- Authenticated user.
- Customer or workspace.
- Event properties.
- Approved custom resolvers.

Do not collect arbitrary cookies or query parameters.

## Historical attribution

Persist permitted attribution observations so they can be resolved after registration or later payment.

Support:

- Anonymous visitors.
- Sessions.
- Verified user associations.
- Multiple acquisition interactions.
- Multiple sessions.
- Attribution timestamps.
- Expiration.
- Provider ownership.
- Consent state.

Do not create one database column per advertising provider.

Use a flexible but validated schema.

Preserve historical observations rather than collapsing all acquisition data into a single last-click value.

## Attribution selection

The host determines the attribution subject.

Providers may define applicable attribution windows and identifier-selection requirements.

The shared store provides historical observations; it does not pretend to reproduce Meta's or Google's own attribution model.

---

# 15. Browser collector resilience

The collector must remain reliable when browser conditions are imperfect.

Support:

- Consent granted after page load.
- Consent withdrawn during a session.
- Browser script blocking.
- Third-party pixel blocking.
- Missing cookies.
- Missing click identifiers.
- Visitors using multiple sessions.
- Visitors who register without marketing consent.
- Backend conversions with no active browser.

A missing advertising identifier is not automatically a system error.

The source domain event should still be processed.

The conversion engine should distinguish between:

- A conversion that occurred.
- A conversion eligible for external delivery.
- A conversion with available attribution.
- A conversion accepted by the provider.
- A conversion later attributed by the provider.

Never collapse these into a single success flag.

---

# 16. Consent and privacy

Consent and privacy must be part of the architecture from the beginning.

Support:

- Consent categories.
- Collection permission.
- Delivery permission.
- Consent timestamps and provenance.
- Withdrawal.
- Provider-specific consent requirements.
- Field expiration.
- Data minimization.
- Deletion.
- Root isolation.

Consent must be evaluated at collection and again before delayed external delivery.

Do not initialize nonessential provider tracking scripts before valid permission where required.

Do not assume hashing personal identifiers eliminates privacy obligations.

Sensitive values must not appear in operational logs or browser configuration.

If account deletion or consent withdrawal occurs while delivery is queued, the pending job must reevaluate eligibility before submission.

---

# 17. Durable conversion and delivery state

Matched conversions require durable persistence.

Distinguish:

**Conversion occurrence**

A logical qualifying business event.

**Delivery obligation**

A requirement to deliver that conversion to a configured provider/channel.

**Delivery attempt**

An individual attempt to send the event.

The model must support multiple destinations and repeated attempts without creating duplicate logical conversions.

Use stable, database-enforced idempotency and uniqueness rules appropriate to the business event and destination.

Never rely solely on in-memory duplicate prevention.

## Transaction safety

An important conversion should not disappear because the process crashes after the business transaction commits but before the background job is queued.

Use transactional outbox patterns or equivalent durable processing where needed.

Do not send conversions for rolled-back actions.

---

# 18. Provider delivery reliability

External API delivery must be asynchronous and must not block primary application requests.

Use ActiveJob and existing Recording Studio conventions.

Requirements:

- Durable queueing.
- Bounded retries.
- Exponential backoff.
- Rate-limit handling.
- Timeouts.
- Retryable and permanent error classification.
- Stable provider deduplication identifiers.
- Concurrent-worker safety.
- Provider outage resilience.
- Consent revalidation.
- Delivery expiration.

## Provider deadlines

Providers may reject conversions that exceed their permitted submission window.

Each adapter must define applicable event-age limits or submission constraints.

The delivery system must stop retrying events that are permanently ineligible due to age.

Do not retry forever.

Keep an auditable terminal failure reason.

## Delivery status

Distinguish:

```text
pending
processing
accepted
retry_scheduled
permanently_failed
suppressed
expired
```

A provider API acceptance is not confirmation of advertising attribution.

---

# 19. Logging using Recording Studio Logs

Use `RecordingStudio_logs` for operational logging, retention and aggregation.

Do not build a parallel generic logging framework.

Log three lifecycle stages:

1. Event observed or received.
2. Conversion matched or suppressed.
3. Delivery attempted and accepted or failed.

Avoid persisting every high-volume observation as a durable conversion row.

Use existing producer logs and aggregates for ordinary Views activity.

## Log properties

Include appropriate references such as:

- Source event ID.
- Canonical event name.
- Source gem.
- Root ID.
- Recording ID and type.
- Conversion occurrence ID.
- Conversion rule.
- Provider.
- Delivery channel.
- Delivery status.
- Attempt count.
- Timestamps.
- Sanitized error category.
- Consent or attribution resolution outcome.

Never store provider secrets or unnecessary personal identifiers.

## Retention

Raw observation logs may use shorter retention periods.

Durable pending deliveries must not be deleted by raw log retention.

Use existing partitioning and root-deletion support.

## Aggregation

Use Recording Studio Logs and Metrics for:

- Events received.
- Conversion matches.
- Deliveries attempted.
- Accepted deliveries.
- Failed deliveries.
- Suppressed conversions.
- Missing attribution.
- Identity-resolution failures.
- Delivery latency.

---

# 20. Recording Studio Admin

All administration screens must use `RecordingStudio_admin`.

Do not create a separate administration framework.

**The interface is read-only.**

Conversion rules, provider registrations and tracking destinations remain configured in code.

Follow existing Recording Studio Admin, Accessible and Flatpack conventions.

## Overview

Display:

- Events received.
- Conversions matched.
- Deliveries pending.
- Deliveries accepted.
- Deliveries failed.
- Suppressed conversions.
- Conversion activity by provider.
- Recent delivery health.

## Event registry

Show available events and their sources.

Example:

| Event | Source gem | Tracked | Last observed |
|---|---|---|---|
| `users.registered` | Users | Yes | 10 min ago |
| `views.recorded` | Views | Yes | 1 min ago |
| `stripe.trial_started` | Stripe | Yes | 2 hours ago |
| `stripe.invoice_paid` | Stripe | Yes | Yesterday |

Show declared event properties and matching conversion rules.

## Conversion mappings

Display:

- Conversion identifier.
- Source event.
- Conditions.
- Destination.
- External event name.
- Browser/server delivery mode.

No edit controls.

## Providers and collection

Display:

- Enabled providers.
- Declared fields.
- Collection sources.
- Required/optional status.
- Conditional requirements.
- Consent requirements.
- Retention policy.
- Browser modules.
- Server capabilities.

Generate this information from the actual adapter registry.

Do not duplicate field definitions in Admin templates.

## Browser tracking

Show:

- Host configuration status.
- Registered browser modules.
- Recent attribution captures.
- Recent collector errors.
- Browser delivery activity.
- Missing attribution trends.

Only claim route or layout coverage where it can actually be measured.

## Event log

Display a chronological view of conversion lifecycles.

Example:

```text
10:42:15 Domain event received
         stripe.trial_started

10:42:15 Conversion matched
         trial

10:42:15 Acquisition identity resolved
         User reference available

10:42:16 Attribution evaluated
         Meta identifiers available

10:42:16 Delivery queued
         Meta Conversions API

10:42:17 Delivery accepted
         Meta API
```

For suppressed events, show the reason.

For failures, show sanitized diagnostics and retry status.

## Delivery health

Show:

- Pending jobs.
- Oldest pending job.
- Retry counts.
- Failed deliveries.
- Provider errors.
- Delivery latency.
- Expired deliveries.

## Conversion coverage

Show registered conversions that:

- Have never matched.
- Have not matched recently.
- Have repeated delivery failures.
- Frequently lack required fields.

Do not classify ordinary low-volume behavior as a failure automatically.

---

# 21. Meta adapter

Implement Meta Ads first.

Required capabilities:

- Meta Pixel browser integration.
- Meta Conversions API.
- Standard and custom events.
- Provider-declared attribution collection.
- Customer matching.
- Correct normalization and hashing.
- Value and currency.
- Shared browser/server event IDs.
- Test Events support.
- Error handling.
- Retry and expiry behavior.

Verify current requirements against official Meta documentation during implementation.

Do not assume that illustrative field names or requirements in this instruction are exhaustive.

The adapter must own all Meta-specific mapping, formatting and submission behavior.

A successful Conversions API response must be reported as accepted, not as definitively attributed.

---

# 22. Installation and host integration

Provide standard Recording Studio installation generators.

Illustrative Gemfile entry:

```ruby
gem "recording_studio_conversions",
    github: "bowerbird-app/RecordingStudio_conversions"
```

Generators should install:

- Initializer.
- Required migrations.
- Browser tracker integration.
- Example event subscriptions.
- Example conversion mappings.
- Example Meta destination configuration.

Tracking must be explicitly enabled by the host.

Illustrative layout integration:

```erb
<head>
  <%= recording_studio_conversions_tags %>
</head>
```

Do not automatically inject tracking into every Recording Studio engine layout.

Applications must boot normally with no providers configured.

Use the Rails asset and JavaScript conventions supported by the existing ecosystem.

Avoid introducing unnecessary frontend frameworks.

---

# 23. Testing requirements

Provide comprehensive tests covering:

### Domain instrumentation

- Independent event subscriptions.
- Canonical event normalization.
- Schema validation.
- Missing source events.
- Transaction rollbacks.
- Duplicate source events.

### Recording Studio Views

- Consumption of Views events.
- Recording and root identification.
- No duplicate view counting.
- Matching specific page or recording conditions.

### Conversion rules

- Multiple rules.
- Multiple destinations.
- Conditional matching.
- First-occurrence uniqueness.
- Stable conversion identifiers.
- Root filtering.

### Attribution identity

- Anonymous visitor collection.
- Verified registration linking.
- Host attribution-subject policy.
- Multi-user workspaces.
- Delayed Stripe payments.
- Missing acquisition identity.
- Ambiguous identity.
- Attribution expiration.

### Provider requirements

- Required and optional fields.
- Conditional requirements.
- Alternative accepted identifiers.
- Transformations.
- Provider-specific event validation.
- Multiple adapters.
- Disabled providers.

### Browser tracker

- Host layout integration.
- Provider module loading.
- Consent changes.
- Missing cookies.
- Script blocking.
- Turbo navigation.
- Duplicate initialization.
- Secure backend collection.
- Server-issued browser conversion receipts.
- Browser/server deduplication.

### Durable delivery

- Process and job retries.
- Idempotency.
- Transaction-safe publication.
- Provider outages.
- Submission deadlines.
- Permanent failures.
- Consent withdrawal while queued.
- Concurrent workers.

### Meta

- Pixel event formatting.
- Conversions API requests.
- Matching event IDs.
- Customer matching fields.
- Correct hashing.
- Provider acknowledgements.
- API errors.
- Test Events support.

### Logs and Admin

- Operational logging.
- Aggregations.
- Retention.
- Root deletion.
- Read-only screens.
- Event discovery.
- Provider field inspection.
- Delivery status visibility.

Mock external APIs.

Create a dummy Rails application demonstrating the integrated workflow.

---

# 24. Implementation milestones

Develop incrementally, but preserve the complete architectural boundaries from the beginning.

## Milestone 1 — Architecture assessment

Inspect existing repositories and identify:

- Reusable instrumentation.
- Views event contracts.
- Required Stripe events.
- Identity association requirements.
- Provider adapter architecture.
- Persistence models.
- Logging and Admin integration.

Document the architecture before implementation.

## Milestone 2 — Event and conversion core

Implement subscriptions, canonical events, conversion definitions and deterministic matching.

## Milestone 3 — Provider declarations

Implement the provider registry and its field, consent, browser and delivery capability declarations.

## Milestone 4 — Attribution and browser collection

Implement the shared tracker, permitted field capture, first-party attribution persistence and secure user association.

## Milestone 5 — Durable delivery infrastructure

Implement conversion occurrences, delivery obligations, asynchronous jobs and operational logging.

## Milestone 6 — Meta integration

Implement Meta Conversions API and Pixel adapters.

## Milestone 7 — First complete integration

Demonstrate:

```text
Visitor clicks Meta ad
          |
          v
Featured In captures permitted attribution
          |
          v
Visitor registers
          |
          v
Host associates acquisition identity
          |
          v
Stripe confirms trial
          |
          v
Stripe emits domain event
          |
          v
Conversions matches StartTrial rule
          |
          v
Attribution and identity resolved
          |
          v
Meta Conversions API receives event
          |
          v
Delivery state logged
```

This is the first required end-to-end acceptance test.

## Milestone 8 — Payment and deduplication

Add confirmed payment tracking, delayed attribution resolution and browser/server deduplication.

## Milestone 9 — Views conversions and Admin

Integrate Recording Studio Views events and deliver the read-only Admin monitoring screens.

## Milestone 10 — Extensibility verification

Implement a minimal mock second adapter with different field requirements to prove that a new provider can be introduced without changes to:

- Domain gems.
- Shared browser tracker.
- Core event registry.
- Attribution storage.
- Conversion matching.
- Delivery orchestration.

This mock adapter is an architectural test, not a production Google Ads integration.

---

# 25. Acceptance criteria

The gem is complete when:

1. Domain gems emit events independently of Conversions.
2. Conversions subscribes using stable event contracts.
3. Recording Studio Views owns canonical page-view observation.
4. Code-defined rules determine which events become conversions.
5. Providers declare the fields they need and their delivery capabilities.
6. The shared browser tracker contains no provider-specific advertising logic.
7. The host explicitly opts into tracking.
8. Anonymous attribution can be linked securely to a registered user.
9. The host explicitly determines the acquisition identity for workspace conversions.
10. Delayed Stripe events can resolve previously captured permitted attribution.
11. Server-authoritative conversions cannot be fabricated from the browser.
12. Browser and server deliveries share appropriate deduplication identifiers.
13. High-volume observations do not automatically become durable conversion records.
14. Matched conversions and pending deliveries are durable.
15. External deliveries are retryable, bounded and idempotent where supported.
16. Consent and retention requirements are enforced.
17. Logging integrates with Recording Studio Logs.
18. Reporting integrates with Recording Studio Metrics.
19. All monitoring uses read-only Recording Studio Admin screens.
20. A second provider adapter can be added without modifying the core infrastructure.

---

# Final instructions to the coding agent

The primary responsibility of Recording Studio Conversions is to transform **provider-neutral application events into eligible, attributable advertising conversions**.

Keep these boundaries explicit:

- Domain gems own business events.
- Recording Studio Views owns page views.
- Providers own their field requirements and delivery protocols.
- The host owns acquisition identity policy.
- Conversions owns attribution collection, identity-resolution infrastructure, conversion matching and delivery orchestration.
- Recording Studio Logs owns operational log infrastructure.
- Recording Studio Metrics owns reusable reporting.
- Recording Studio Admin owns administration.

Do not introduce unnecessary coupling between these systems.

Do not implement advertising logic inside Stripe, Pages, Press Kits or other domain gems.

Do not turn Conversions into a generic page-view analytics system or marketing automation platform.

**Before writing code, produce an architecture assessment based on the actual current repositories. Then implement a complete Meta trial-conversion flow first, followed by payments, browser/server deduplication, Views integration and operational Admin screens.**

The end result must be a stable, independently reusable Recording Studio gem capable of supporting additional advertising providers without architectural changes.
