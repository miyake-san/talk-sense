# ADR-004 — Real-Time Metrics Architecture with Event Hubs and Microsoft Fabric

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

TalkSense already implements the foundation of the selected streaming path:

```text
Voice agent → Azure Event Hubs → Fabric Eventstream → Eventhouse/KQL → Power BI
```

The repository provisions Event Hubs with Bicep and Terraform, documents a `fabric-eventstream` consumer group, defines `RawTelemetry`, `Conversations`, `Turns`, `Events`, and `CSAT` KQL tables, and provides nine initial metrics. The current contract has four top-level event types: `conversation_started`, `turn_completed`, `conversation_event`, and `csat_received`.

The contract lacks a stable event ID, schema version, tenant and trace conventions, sequence number, privacy classification, model/agent version, audio-quality events, tool-call events, token usage, evaluation results, and explicit completion semantics. Event Hubs and Eventstream provide at-least-once delivery; duplicates, retries, late events, and out-of-order events must therefore be expected.

Application Insights and Log Analytics are appropriate for runtime diagnostics and distributed traces. Event Hubs and Fabric are appropriate for governed conversation, call, business, and AI-operational events. Neither should be forced to replace the other.

## Decision

Retain and extend the current event-driven architecture:

1. The channel/session backend, orchestrator, tools, mining pipeline, and approved platform adapters emit versioned events to Azure Event Hubs.
2. Producers use `conversationId` as the Event Hubs partition key so events for a conversation are ordered within one partition.
3. Fabric Eventstream consumes through its own consumer group, performs only routing and safe normalization, and writes an append-only landing table in Eventhouse.
4. Version-aware KQL update policies materialize typed tables. Direct Eventstream-to-table routing can be introduced later for stable, high-volume event types after replay and parity tests.
5. Eventhouse serves realtime KQL dashboards, alerting, and operational drill-through.
6. OneLake availability and curated Lakehouse tables serve historical analytics, ontology, data science, and Power BI Direct Lake. They are not the source for sub-minute alerts.
7. Application Insights remains the diagnostic source for exceptions, dependency spans, and code-level traces. Only approved, low-cardinality analytical projections are copied into Event Hubs.

### Event envelope

Adopt a CloudEvents 1.0 structured JSON envelope while supporting a transition from the existing `eventType` payloads. Custom CloudEvents extension attributes use lowercase names; Eventhouse normalization maps them to the repository's camel-case column convention:

```json
{
  "specversion": "1.0",
  "id": "01JZQ8S4M4H0A7M4W3Q2Y0B2J6",
  "type": "com.talksense.turn.completed.v2",
  "source": "/talksense/session-api",
  "subject": "/conversations/conv_01JZQ8",
  "time": "2026-07-29T15:31:33.189Z",
  "datacontenttype": "application/json",
  "dataschema": "urn:talksense:schema:turn-completed:2",
  "schemaversion": "2.0",
  "tenantid": "tenant_01",
  "conversationid": "conv_01JZQ8",
  "sessionid": "sess_01JZQ7",
  "correlationid": "corr_01JZQ7",
  "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  "sequence": 17,
  "privacyclass": "pseudonymous",
  "redactionpolicy": "conversation-pii-v2",
  "producername": "session-api",
  "producerversion": "2.3.0",
  "producerregion": "brazilsouth",
  "data": {
    "turnId": "turn_17",
    "speaker": "assistant",
    "intent": "invoice_copy",
    "responseLatencyMs": 842,
    "outcome": "answered"
  }
}
```

`id` is globally unique and immutable. `sequence` is monotonic only within a conversation and producer epoch; consumers still use event time and tolerate gaps. The schema is stored in source control, reviewed for backward compatibility, and optionally published to Azure Schema Registry. Producers must not silently change a field's meaning or unit.

### Event catalog

The initial catalog preserves mappings from the four existing event types and adds:

- `conversation.started`, `consent.updated`, and `conversation.completed`;
- `turn.completed` and `turn.interrupted`;
- `voice.quality.sampled` and `voice.session.disconnected`;
- `agent.invocation.completed` and `agent.tool.completed`;
- `model.usage.recorded`;
- `handoff.requested`, `handoff.completed`, and `handoff.failed`;
- `mining.completed` and `evaluation.completed`;
- `policy.flagged` and `policy.reviewed`;
- `csat.received`;
- `error.occurred`.

Payloads contain identifiers, classifications, timings, outcomes, counts, scores, and evidence references. They do not contain raw audio, credentials, authentication factors, payment data, full tool arguments/results, or unredacted transcript text.

### Eventhouse tables

Preserve the current tables and add purpose-specific append-only tables:

| Table | Purpose |
| --- | --- |
| `RawTelemetry` | Short-retention canonical landing envelope, ingestion diagnostics, and replay source |
| `Conversations` | Start/end, channel, locale, duration, outcome, containment, consent class |
| `Turns` | Per-turn actor, intent/topic IDs, latency, interruption, outcome, safe text reference |
| `Events` | Existing generic business events during schema transition |
| `CSAT` | Explicit survey responses and response metadata |
| `VoiceQuality` | Windowed RTT, jitter, packet loss, audio gaps, codec, reconnects |
| `AgentInvocations` | Orchestrator/specialist version, duration, result, retry, error class |
| `ToolCalls` | Approved tool name/version, duration, result, validation and authorization outcome |
| `ModelUsage` | Deployment/version and supported input/output/audio token or unit counts |
| `Escalations` | Request reason, queue, transfer status, wait time, human acceptance, outcome |
| `MiningResults` | Pipeline/analyzer version, status, extracted counts, confidence and processing latency |
| `Evaluations` | Evaluator/version, sampled population, score, threshold, pass/fail |
| `PolicyFindings` | Candidate/confirmed status, policy ID/version, severity, review disposition |

Each typed table retains `eventId`, `schemaVersion`, `tenantId`, `conversationId`, event time, ingestion time, producer version, and trace correlation. Materialized views and metric queries deduplicate by `eventId`, select the latest correction by version/time where applicable, and report duplicate/late-event rates.

### Metric definitions

| Metric | Definition and cautions |
| --- | --- |
| Response latency | p50/p95/p99 time from end-of-user-turn to first assistant audio, plus tool and full-turn latency as separate measures |
| Audio quality | RTT, jitter, packet loss, gap duration, reconnect and abnormal-disconnect rates by channel/codec/region |
| Containment rate | Eligible completed conversations resolved without human transfer divided by eligible completed conversations; exclude tests, mandated transfers, and caller abandonment according to a versioned eligibility rule |
| Escalation rate | Conversations with requested and completed handoff reported separately; divide by the same eligible population |
| Average handle time | End minus start for completed contacts, segmented into automated time, queue wait, and human time where available |
| Sentiment | Customer sentiment distribution and trend with model/version and confidence; never compare incompatible model versions without calibration |
| Satisfaction proxy | A clearly labeled composite from sentiment, outcome, repeat-contact, and CSAT. Rename the current CSAT-derived measure to `SatisfactionProxy`; it must not be called NPS because actual NPS requires the standard survey question and calculation |
| Policy findings | Candidate and human-confirmed findings per policy/severity; confirmed violation rate excludes pending review |
| Agent/tool behavior | Invocations, tool calls per conversation, selection/input validity, authorization denial, success, timeout, retry, and latency |
| Model usage | Supported text/audio input and output units, cost allocation tags, cache use, throttling, and quota saturation |
| Error rate | Failures per eligible operation by layer and error class; caller-visible and recovered errors reported separately |

Metric definitions, denominator rules, units, exclusions, taxonomy versions, and owners are versioned in the semantic model and data catalog.

## Options Considered

### Option A — Producers write directly to Fabric Eventstream

Rejected for production. It removes the Azure buffering/replay boundary, couples application availability to Fabric, and provides weaker producer isolation. It can be useful for a short Fabric-only demonstration.

### Option B — Producers write directly to Eventhouse

Rejected. It couples every producer to KQL ingestion and schema details and weakens independent replay and consumer scaling.

### Option C — Event Hubs to Eventstream to Eventhouse

Selected. It matches the existing repository and provides producer decoupling, partitions, retention, replay, independent consumer groups, Eventstream routing, and realtime KQL.

### Option D — Application Insights and Log Analytics only

Rejected as the business analytics architecture. It is retained for operational diagnostics, but high-volume domain events, semantic business metrics, OneLake integration, and Fabric analytics need a separate governed stream.

### Option E — Send full transcripts in every event

Rejected. It increases cost, duplication, privacy exposure, deletion complexity, and accidental trace/report disclosure. Events carry redacted snippets only when explicitly approved; otherwise they carry a restricted artifact or search-document reference.

## Consequences

### Positive

- Extends the implemented architecture rather than replacing it.
- Decouples application, mining, Fabric, monitoring, and future consumers.
- Supports replay, late data, versioned contracts, and conversation-local ordering.
- Makes AI/model/tool and media quality observable alongside business outcomes.
- Gives realtime operations KQL while retaining OneLake and Power BI for historical analysis.

### Negative

- At-least-once delivery requires idempotent producers where possible and deduplicating consumers everywhere.
- Raw plus typed tables increase storage and schema-management work.
- Event correction, replay, and reprocessing need explicit semantics.
- Power BI Direct Lake freshness follows OneLake materialization, which can range from minutes to hours; it is not equivalent to Eventhouse realtime freshness.
- Eventhouse/OneLake security, retention, purge, and schema-change constraints require coordinated operations.

## Security and Governance Considerations

- Use Microsoft Entra ID and managed identities for producers and consumers in production. Retain SAS send/listen policies only for isolated development compatibility and rotate them through Key Vault.
- Grant producers send-only access and Fabric receive-only access. Use a separate consumer group and identity per consumer.
- Require TLS, disable public access where the end-to-end supported topology allows it, and validate Fabric managed-private-endpoint support before asserting full private connectivity.
- Do not assume a direct Event Hubs-to-Eventhouse private-link path. Document and test the actual Eventstream network boundary in each target region.
- Validate `tenantId`, schema, size, event type, timestamp skew, privacy class, and allowed fields before publication. Quarantine invalid events.
- Pseudonymize customer identifiers and prohibit direct identifiers in the envelope. Treat free text and tool payloads as restricted by default.
- Apply Fabric workspace roles, KQL table/database permissions, semantic-model RLS/OLS, sensitivity labels, DLP, and audit logging. KQL security and Power BI/OneLake security are separate enforcement points.
- Account for Event Hubs retention, Eventhouse soft-delete/cache, OneLake copies, exports, and backups in deletion and legal-hold procedures.

## Observability and Evaluation

Monitor the streaming system itself:

- producer success, throttling, batch size, serialization failure, and event-size distribution;
- incoming messages, throughput units/processing units, partition skew, consumer lag, and retention headroom;
- Eventstream source/destination health, transformation failures, invalid schema, and delivery latency;
- Eventhouse ingestion latency, rejected records, update-policy failures, duplicate IDs, late events, table growth, cache hit, and KQL query latency;
- OneLake materialization lag and Power BI semantic-model freshness;
- end-to-end reconciliation between conversation starts, completions, turns, transfers, mining results, and CSAT.

Use contract tests for every producer, golden JSON samples for every schema version, replay tests, duplicate/out-of-order tests, and synthetic end-to-end probes. Alert on sustained lag, missing completion events, schema rejection, abnormal duplicate rates, partition hotspots, metric discontinuities, and divergence between operational and analytical totals.

## Implementation Notes

1. Inventory the current four payloads and publish a version-1 JSON Schema without changing behavior.
2. Introduce `id`, `schemaVersion`, correlation, sequence, producer, and privacy fields as backward-compatible additions.
3. Create the version-2 CloudEvents-compatible envelope and a temporary normalization path for version 1.
4. Add `eventId` and schema/correlation columns to the existing KQL tables before adding new event types.
5. Implement `VoiceQuality`, `AgentInvocations`, `ToolCalls`, `ModelUsage`, `Escalations`, `MiningResults`, `Evaluations`, and `PolicyFindings` incrementally.
6. Reconcile update-policy output against Eventstream direct-routing output before retiring either path.
7. Add realtime KQL dashboards and alerts, then update the Power BI semantic model for historical measures.
8. Size partitions, throughput, retention, cache, and Fabric capacity from measured event size and peak call concurrency rather than repository defaults.

Primary references:

- [Azure Event Hubs overview](https://learn.microsoft.com/azure/event-hubs/event-hubs-about)
- [Azure Event Hubs features and terminology](https://learn.microsoft.com/azure/event-hubs/event-hubs-features)
- [Add Azure Event Hubs as a Fabric Eventstream source](https://learn.microsoft.com/fabric/real-time-intelligence/event-streams/add-source-azure-event-hubs)
- [Microsoft Fabric Eventhouse overview](https://learn.microsoft.com/fabric/real-time-intelligence/eventhouse)
- [OneLake availability for Eventhouse](https://learn.microsoft.com/fabric/real-time-intelligence/event-house-onelake-availability)
- [CloudEvents specification](https://github.com/cloudevents/spec)

## Open Questions

- What are peak concurrent calls, events per turn, average payload size, retention, and replay objectives?
- Which events require corrections, and how should corrections supersede prior facts?
- Is Event Hubs Capture required for replay beyond Event Hubs and `RawTelemetry` retention?
- Which regions and network topology allow the required Eventstream-to-Event Hubs private connectivity?
- What are the realtime KQL, OneLake, and Power BI freshness service-level objectives?
- Which metric definitions and eligible populations are approved by operations, finance, compliance, and customer-experience owners?
- Which identifiers may cross tenant, region, analytics, and support boundaries?
- How will schema compatibility be enforced across independently deployed voice, agent, tool, and mining producers?
