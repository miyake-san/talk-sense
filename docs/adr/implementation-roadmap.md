# TalkSense Microsoft Platform Implementation Roadmap

## Purpose

This roadmap converts ADR-001 through ADR-007 into sequenced, issue-sized implementation work. It does not include delivery estimates. Each checkbox is intended to become a GitHub issue with an owner, acceptance criteria, dependencies, risk classification, and validation evidence.

## Current-state findings

TalkSense is currently a documented analytics/IaC reference implementation:

- Azure Event Hubs is provisioned through Bicep and Terraform.
- Fabric Eventstream and Eventhouse/KQL setup is manual.
- The event contract covers conversation start, completed turns, generic conversation events, and CSAT.
- Eventhouse uses `RawTelemetry`, `Conversations`, `Turns`, `Events`, and `CSAT`.
- Power BI assets and synthetic sample data validate the initial metrics.
- Development infrastructure permits SAS/local authentication and public networking.
- No frontend/backend, voice transport, Foundry agent, Cosmos implementation, Search index, Content Understanding pipeline, automated tests, or CI workflow is present.

## Working assumptions

1. The Event Hubs → Eventstream → Eventhouse → Power BI path remains the analytical backbone.
2. The live call remains independent of Fabric availability and publishing telemetry never blocks a safe response or transfer.
3. Browser WebRTC precedes production SIP.
4. Application language, compute, identity, CRM, contact center, and carrier choices require explicit decisions.
5. Real recordings are unavailable until purpose, consent, privacy, retention, and security controls are approved.
6. All customer identifiers outside the authoritative system are scoped pseudonyms.
7. Event Hubs/Fabric/Search receive redacted content only.
8. Preview capabilities require a fallback and cannot be a production security boundary.
9. Existing documentation values and capacity defaults are hypotheses until load-tested.
10. ADRs remain Proposed until accountable architecture, product, privacy, security, operations, and data owners approve them.

## Sequencing principles

- Build a text and identity boundary before voice.
- Build consent, handoff, and safe fallback before recording or automation with side effects.
- Build the versioned event contract before adding producers.
- Build restricted storage, redaction, and deletion before mining real calls.
- Establish certified metrics before ontology and Data Agents.
- Prove browser behavior before carrier/SIP integration.
- Treat security, observability, evaluation, and operational readiness as acceptance criteria in every phase.

## Phase 0 — Approve scope and architecture

- [ ] **Issue: Approve ADR-001 through ADR-007** — Record owners, reviewers, conditions, rejected alternatives, and any required follow-up ADRs.
- [ ] **Issue: Define supported customer journeys** — Identify intents, transactions, prohibited uses, authentication levels, policy boundaries, and mandatory handoff scenarios.
- [ ] **Issue: Define service objectives** — Approve live-call latency/availability, analytics freshness, mining completion, RTO/RPO, data-quality, and safety objectives.
- [ ] **Issue: Select the application stack and Azure compute** — Decide frontend/backend languages, WebSocket/media requirements, App Service versus Container Apps, and repository layout.
- [ ] **Issue: Select identity and source systems** — Identify customer/employee identity, CRM, case, product, policy, workforce, and human-agent systems of record.
- [ ] **Issue: Select target regions and feature policy** — Validate service availability, data residency, model quota, Fabric capacity, private networking, and allowed preview features.
- [ ] **Issue: Establish architecture ownership** — Assign accountable owners for channels, agents, tools, data products, ontology, metrics, privacy, security, and operations.

## Phase 1 — Establish the secure platform foundation

- [ ] **Issue: Create environment isolation** — Define development, test, and production subscriptions/resource groups, Foundry projects, Fabric workspaces, identities, data stores, and budgets.
- [ ] **Issue: Extend IaC with identity and Key Vault** — Provision workload managed identities, least-privilege role assignments, Key Vault, rotation, and privileged-access controls.
- [ ] **Issue: Implement private network topology** — Add VNets, subnets, private endpoints, private DNS, controlled egress, WAF/API edge, and documented exceptions.
- [ ] **Issue: Provision application observability** — Add Application Insights, Log Analytics, dashboards, alerts, protected sensitive-trace configuration, and SIEM routing.
- [ ] **Issue: Harden Event Hubs production authentication** — Disable inappropriate local/SAS access, configure managed-identity producer/consumer roles, and retain isolated development compatibility only where needed.
- [ ] **Issue: Establish repository CI and validation** — Add existing-tool lint/build/test automation, IaC validation, Markdown/link checks, schema checks, secret scanning, and environment promotion.
- [ ] **Issue: Define deployment manifests** — Version application, model, prompt, agent, tool, knowledge-index, policy, schema, and infrastructure releases together.

## Phase 2 — Deliver a secure text-agent vertical slice

- [ ] **Issue: Build the session and channel API** — Implement identity/anonymous boundaries, tenant context, rate limits, correlation, consent state, and text streaming.
- [ ] **Issue: Provision Cosmos DB operational state** — Define containers, partition strategy, TTL, optimistic concurrency, encryption, network controls, and deletion behavior.
- [ ] **Issue: Deploy the Conversation Orchestrator** — Implement bounded tool selection, structured results, latency budgets, retries, failure handling, and versioned instructions.
- [ ] **Issue: Build the knowledge ingestion path** — Curate sources, permissions, chunking, embeddings, index versioning, citations, and document deletion in Azure AI Search/Foundry IQ.
- [ ] **Issue: Implement the Knowledge Agent** — Add permission-aware grounded retrieval, citation checks, uncertainty handling, and no-answer behavior.
- [ ] **Issue: Implement Policy/Compliance controls** — Add versioned policy sources, an advisory agent, deterministic policy checks, and approved refusal/escalation behavior.
- [ ] **Issue: Implement structured human handoff** — Create transfer reasons, queue eligibility, redacted handoff package, mock human acceptance, and failed-transfer fallback.
- [ ] **Issue: Build the agent evaluation harness** — Add golden conversations for intent, grounding, citations, policy, tool choice, PII, safety, and handoff.

## Phase 3 — Add the browser realtime voice prototype

- [ ] **Issue: Build the WebRTC session broker** — Issue short-lived constrained sessions or proxy SDP without exposing long-lived model credentials.
- [ ] **Issue: Build the browser voice client** — Add media permission, device selection, connection state, accessibility, AI/recording notice, and text fallback.
- [ ] **Issue: Integrate Foundry realtime audio** — Configure the supported GA endpoint/model, locale, voice, VAD, tools, quotas, and server control.
- [ ] **Issue: Implement interruption and barge-in** — Stop playback, cancel generation, truncate unplayed context, clear buffers, deduplicate events, and test races.
- [ ] **Issue: Finalize ordered transcripts** — Reconcile realtime transcript events, speaker turns, interruptions, timestamps, and authoritative completion.
- [ ] **Issue: Implement voice degradation paths** — Add bounded reconnect, transport failure messaging, text fallback, human handoff, and callback capture.
- [ ] **Issue: Emit voice quality telemetry** — Capture setup time, RTT, jitter, packet loss, gaps, codec, reconnects, no-input/no-match, and abnormal closure.
- [ ] **Issue: Run voice quality and accessibility tests** — Test languages, accents, noise, echo, packet impairment, interruptions, devices, and assistive scenarios.

## Phase 4 — Build conversation knowledge mining

- [ ] **Issue: Provision restricted recording/transcript storage** — Add consent-gated landing containers, private access, encryption, malware controls, retention, and audit.
- [ ] **Issue: Build the durable after-call workflow** — Add Event Grid/Service Bus, idempotency, retries, dead letters, concurrency, and replay.
- [ ] **Issue: Define canonical transcript and enrichment schemas** — Include turns, roles, timestamps, provenance, evidence, confidence, and pipeline/model/taxonomy versions.
- [ ] **Issue: Configure Content Understanding audio analysis** — Validate formats/locales/limits and implement transcription, diarization, role detection, and custom extraction.
- [ ] **Issue: Implement conversational PII redaction** — Combine deterministic rules and Azure AI Language, preserve typed placeholders, quarantine failures, and measure leakage.
- [ ] **Issue: Implement Azure OpenAI structured enrichment** — Extract topics, key phrases, sentiment, entities, relationships, summaries, actions, outcomes, and candidate compliance flags.
- [ ] **Issue: Add compliance review workflow** — Apply deterministic rules, evidence links, human disposition, policy version, severity, and audit.
- [ ] **Issue: Index redacted conversations** — Add chunking, embeddings, ACL metadata, hybrid retrieval, citations, index versioning, and delete/reindex behavior.
- [ ] **Issue: Implement mining evaluation and reconciliation** — Compare live labels with after-call labels and validate extraction, evidence, redaction, and retrieval quality.

## Phase 5 — Evolve realtime metrics and reporting

- [ ] **Issue: Version the current event contract** — Publish JSON Schemas, units, compatibility policy, producer rules, golden samples, and privacy classification.
- [ ] **Issue: Introduce the CloudEvents-compatible envelope** — Add event ID, schema version, tenant/session/conversation/trace correlation, sequence, producer, and redaction policy.
- [ ] **Issue: Add AI, voice, handoff, mining, policy, and evaluation events** — Implement the ADR-004 event catalog without transcript or secret payloads.
- [ ] **Issue: Extend Eventhouse schemas and update policies** — Add idempotent typed tables, deduplication, correction/replay semantics, retention, and version-aware parsing.
- [ ] **Issue: Configure and automate Fabric Eventstream** — Implement source identity/networking, routing, invalid-event handling, destination monitoring, and environment promotion.
- [ ] **Issue: Build realtime KQL metrics and alerts** — Add certified latency, quality, containment, escalation, handle-time, policy, tool, usage, and error functions.
- [ ] **Issue: Extend the Power BI semantic model** — Add conformed dimensions, historical metrics, definition versions, RLS/OLS, freshness disclosure, and report changes.
- [ ] **Issue: Reconcile operational and analytical counts** — Compare source sessions, Event Hubs, Eventstream, Eventhouse, OneLake, and Power BI totals under duplicate/late/replay tests.
- [ ] **Issue: Load-test the streaming path** — Validate partitions, throughput, lag, Eventhouse capacity/cache, OneLake latency, query performance, and cost.

## Phase 6 — Add Fabric semantics and Data Agents

- [ ] **Issue: Create the support-domain glossary** — Approve entity, relationship, metric, SLA, synonym, owner, privacy, and effective-date definitions.
- [ ] **Issue: Build curated Lakehouse dimensions and facts** — Materialize conformed Customer, Call, Conversation, Intent, Topic, Agent, HumanAgent, Case, Product, Policy, Escalation, Metric, SLA, and Event data.
- [ ] **Issue: Reconcile certified KQL and semantic measures** — Ensure realtime and historical calculations use the same populations, units, timezones, and versioned definitions.
- [ ] **Issue: Prototype Fabric Ontology** — Bind approved Eventhouse and Lakehouse entities in nonproduction and evaluate preview stability, security, lineage, and promotion.
- [ ] **Issue: Build the Operations Data Agent** — Scope Eventhouse access, add certified KQL examples, freshness rules, aggregation defaults, and denial policies.
- [ ] **Issue: Build the Business Intelligence Data Agent** — Scope semantic/Lakehouse access, add bilingual business terms, certified measures, source citations, and suppression rules.
- [ ] **Issue: Evaluate Data Agent correctness and security** — Run golden NL2KQL/SQL/DAX questions, identity tests, injection tests, numerical reconciliation, and Portuguese-language tests.
- [ ] **Issue: Connect the Metrics Agent** — Route read-only analytical questions to the correct scoped Data Agent with timeout, provenance, and fallback.

## Phase 7 — Integrate SIP and the contact center

- [ ] **Issue: Select the telephony architecture** — Decide direct realtime SIP versus ACS/Voice Live adapter using the target carrier, PBX/SBC, contact center, recording, and transfer needs.
- [ ] **Issue: Complete a SIP interoperability proof of concept** — Validate TLS/SRTP, codecs, DTMF, signed inbound events, call control, region, failover, and capacity.
- [ ] **Issue: Implement telecom consent and recording controls** — Synchronize notices, recording state, withdrawal, conference/transfer behavior, artifact storage, and audit.
- [ ] **Issue: Integrate contact-center routing and handoff** — Transfer to approved queues, preserve verification/context, display a redacted summary, and confirm human acceptance.
- [ ] **Issue: Implement telephony fraud and abuse controls** — Add destination allow-lists, rate/cost limits, anomaly detection, caller verification, and incident response.
- [ ] **Issue: Validate degraded telephony behavior** — Test model/tool outage, carrier failure, failed transfer, queue timeout, callback, and emergency/prohibited scenarios.
- [ ] **Issue: Run a controlled human-supervised pilot** — Use approved callers/data, monitor every transfer and safety event, and define stop criteria.

## Phase 8 — Complete production readiness

- [ ] **Issue: Implement cross-store retention and deletion** — Cover Blob/ADLS, Cosmos DB, Search/embeddings, Eventhouse, OneLake/Lakehouse, Power BI, traces, caches, exports, backups, and legal holds.
- [ ] **Issue: Complete security and privacy testing** — Perform threat-model review, penetration testing, access review, tenant-isolation tests, PII leakage tests, and incident exercises.
- [ ] **Issue: Complete Responsible AI red teaming** — Test direct/indirect prompt attacks, harmful content, grounding, task adherence, tool abuse, bias, safety, and handoff.
- [ ] **Issue: Test disaster recovery and restore** — Validate regional degradation, realtime-session fallback, queue replay, data restore, DNS/identity recovery, and RTO/RPO.
- [ ] **Issue: Establish SLO dashboards and on-call runbooks** — Cover live voice, agents/tools, mining, streaming, Fabric, data quality, security, deletion, and Data Agents.
- [ ] **Issue: Complete performance and cost governance** — Load-test peak calls and analytics, set quotas/budgets/alerts, and approve capacity and unit economics.
- [ ] **Issue: Complete accessibility and localization review** — Validate supported languages, notices, text/voice alternatives, assistive technology, and human escalation.
- [ ] **Issue: Obtain production governance approvals** — Record privacy, legal, records, security, Responsible AI, telecom, data, architecture, product, and operations sign-off.
- [ ] **Issue: Run go-live and rollback rehearsal** — Verify deployment, canary, feature flags, rollback, model/prompt/index compatibility, communications, and stop authority.

## Production exit criteria

Production adoption requires:

- accepted ADRs and documented exceptions;
- approved purposes, consent, privacy, retention, deletion, security, and AI risk controls;
- successful end-to-end functional, load, resilience, security, privacy, accessibility, and evaluation evidence;
- measured SLOs and capacity for the expected peak;
- working human handoff and safe degradation independent of Fabric;
- source-to-dashboard reconciliation and certified metric definitions;
- tested on-call, incident, deletion, restore, rollback, and vendor-escalation runbooks;
- named accountable owners for every service, data product, model, agent, tool, policy, and control.
