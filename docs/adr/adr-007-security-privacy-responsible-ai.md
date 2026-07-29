# ADR-007 — Security, Privacy, Compliance, and Responsible AI

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

Voice support data can contain names, government and account identifiers, contact details, authentication factors, payment information, financial or health context, employee data, precise timestamps, inferred sentiment, and a voice recording. Pseudonymous identifiers, transcripts, embeddings, model prompts, tool arguments, traces, summaries, and inferred attributes can still be personal data.

TalkSense documentation already recommends customer-ID hashing, transcript masking, retention, Power BI RLS, Key Vault, managed identity, and private endpoints. However:

- the event-format guide demonstrates unsalted SHA-256 while the telemetry plan recommends keyed HMAC-SHA256;
- current Bicep/Terraform development defaults permit SAS/local authentication and public networking;
- no consent, recording, deletion, legal-hold, identity, Key Vault, private-network, audit, safety, evaluation, or incident-response implementation exists;
- Power BI RLS does not secure direct KQL, OneLake, Search, Blob, or operational-store access;
- a repository statement that the solution is “LGPD/GDPR compliant” cannot be substantiated by architecture documentation alone.

Compliance depends on purpose, jurisdiction, organization, data, contracts, operating procedures, and legal review. This ADR defines technical controls and a release gate; it is not legal advice or a declaration of compliance.

## Decision

Adopt privacy by design, zero trust, defense in depth, and human accountability across every ADR. No production voice workload launches until an accountable privacy/legal/security/Responsible-AI review approves the data inventory, purposes, consent rules, retention, risk assessment, threat model, and operational controls.

### Data classification and minimization

Classify data before collection:

| Class | Examples | Default treatment |
| --- | --- | --- |
| Prohibited from model/analytics | Passwords, PINs, one-time codes, CVV, full payment credentials, secrets, access tokens | Interrupt capture, use a dedicated compliant flow, never log or index |
| Restricted direct identifiers | Name, CPF or other government ID, account number, phone, email, address | Keep only in authoritative source/restricted vault; tokenize or redact elsewhere |
| Restricted conversation content | Raw audio, unredacted transcript, prompts, tool arguments/results, case notes | Private storage, narrow privileged access, short retention |
| Pseudonymous operational data | Scoped customer token, conversation ID, case token, coarse segment | Allowed only for approved purpose with access and retention controls |
| Derived sensitive data | Sentiment, vulnerability, policy flags, inferred intent, risk, employee performance | Record provenance/confidence; restrict use and adverse decisions |
| Aggregate data | Metrics that meet approved aggregation/suppression rules | Preferred for Fabric, dashboards, and broad business access |

Collect the minimum content needed for the declared purpose. Do not use support recordings for voiceprints, speaker identity, model training, employee discipline, marketing, or unrelated profiling without a separately approved purpose and control set.

### Pseudonymization and redaction

- Treat `customerIdAnon` as a **pseudonym**, not anonymous data.
- Replace plain SHA-256 examples with HMAC-SHA256 using a tenant/environment-scoped secret key in Key Vault, or an approved tokenization service. Never hash a low-entropy identifier without a secret.
- Keep the reidentification mapping only in the authoritative CRM/identity system under separate authorization. Analytics services receive no reverse map.
- Include key/version scope so tokens can rotate. Design controlled linkage or reprocessing before rotation; do not retain old keys indefinitely without purpose.
- Combine deterministic rules for known identifiers and secrets with Azure AI Language Conversation PII for multi-turn transcript redaction.
- Redact before Event Hubs, Eventhouse, OneLake, Search, Data Agents, Power BI, ordinary logs, and ordinary traces.
- Use typed placeholders such as `[PERSON_1]` and `[ACCOUNT_1]` when conversation coherence requires stable references. Do not reveal the original value through metadata.
- Evaluate residual PII leakage. Failed or uncertain redaction routes to quarantine or privileged review, not normal analytics.

### Consent and recording boundary

Implement a deterministic consent state machine with `pending`, `granted`, `declined`, `withdrawn`, `expired`, and legally approved `not_required` states. Record the jurisdiction/rule, purpose, policy and notice version, language, channel, timestamp, result, and minimal evidence.

1. Give a clear AI/recording notice before persistent recording or transcript storage.
2. Obtain explicit consent when required. Distinguish service processing, recording, analytics/quality use, and any model-improvement use; do not bundle optional purposes.
3. Before consent, permit only the transient media processing necessary to present the notice and understand the response, where legally approved. Do not persist pre-consent audio/transcript content.
4. If the caller declines, stop recording and offer an approved nonrecorded transient flow, text channel, or human transfer. If the service cannot legally or technically continue, explain and terminate safely.
5. Display or play an ongoing recording indicator where required and propagate consent state through transfers and conferences.
6. Withdrawal stops future persistence immediately and initiates deletion where the legal basis and policy require it.

The application enforces consent. A prompt or agent statement is not the enforcement control.

### Retention and deletion

Use a centrally owned, jurisdiction-aware retention matrix. The following pilot targets are maximum operational defaults pending written legal and records-management approval:

| Data | Pilot target |
| --- | --- |
| Ephemeral media buffers | Session lifetime only; clear on close/failure |
| Raw audio and unredacted transcripts | Collection disabled unless approved; when enabled, 30 days |
| Redacted operational conversation history in Cosmos DB | 90 days |
| Pseudonymous `RawTelemetry` and standard operational logs | 90 days |
| Redacted enriched facts, search chunks/embeddings, and curated analytics | 365 days |
| Consent evidence, security audit, confirmed legal records | Organization schedule defined by legal/records owner; legal hold overrides deletion |

Shorter purpose- or jurisdiction-specific periods override these targets. A longer period requires a documented purpose, owner, and approval. Backups, soft delete, versions, exports, and caches are included in the retention inventory.

Implement one deletion/orchestration workflow that:

1. resolves the data subject in the authoritative system and derives all scoped pseudonyms;
2. applies legal-hold and authorization checks;
3. blocks new processing/reindexing;
4. deletes eligible Blob/ADLS objects, versions, snapshots, and temporary analyzer outputs;
5. deletes Cosmos DB history and processing state;
6. deletes Azure AI Search documents and embeddings;
7. purges or tombstones eligible Eventhouse and Lakehouse/OneLake data using the documented service procedure;
8. refreshes or deletes Power BI imported/derived copies, evaluation datasets, caches, and approved exports;
9. records content-free proof of completion and exceptions.

Event Hubs does not provide per-event deletion, so events must contain no direct PII and use short retention. Where Eventhouse OneLake availability prevents a required purge or schema operation, use an approved runbook to pause/disable availability, purge both representations, validate deletion, and restore service. Document when immutable backups expire rather than falsely reporting immediate physical deletion.

### Identity, secrets, network, and encryption

- Use Microsoft Entra ID and managed identities for service-to-service access. Give each application, agent, pipeline stage, and Fabric connector a distinct least-privilege identity.
- Disable local/key authentication and SAS in production where the service supports Entra ID. Development exceptions are isolated, time-limited, rotated, and monitored.
- Store unavoidable secrets, certificates, HMAC keys, and connection material in Key Vault with RBAC, private endpoint, soft delete, purge protection, rotation, and access logging.
- Use private endpoints, default-deny network rules, private DNS, controlled egress, and approved VNet integration for Foundry dependencies, Cosmos DB, Storage, Search, Event Hubs, Key Vault, registry, and Azure Monitor where supported.
- Put a WAF/API gateway and denial-of-service controls at required public channel edges. Never expose storage, tools, or data-plane endpoints directly to customers.
- Encrypt in transit with current TLS and at rest with platform encryption. Use customer-managed keys only when required and after key availability, rotation, recovery, and separation-of-duties are designed.
- Use RBAC, privileged identity management, just-in-time elevation, access reviews, break-glass controls, and separate production administration.
- Enable Azure, Foundry, Fabric, data-plane, Key Vault, and administrator audit logs. Route security signals to the approved SIEM and incident-response process.

### Agent and model safety

- Complete a Responsible AI impact assessment, privacy impact assessment, threat model, abuse-case review, and use-case classification before production.
- Disclose that the caller is interacting with AI and provide an accessible human-handoff path.
- Apply Foundry guardrails and Azure AI Content Safety at supported user-input, tool-call, tool-response, and output intervention points. Revalidate feature status per model and region.
- Do not assume guardrails cover audio-model processing. Run approved transcript text through separate PII, prompt-attack, content-safety, and policy controls where required.
- Use Prompt Shields and indirect-prompt-attack defenses. Treat transcripts, retrieved documents, webpages, emails, tool results, and attachments as untrusted data, not instructions.
- Allow-list tools and destinations. Use typed schemas, bounded inputs/results, tenant filters, timeouts, rate limits, output encoding, and egress controls.
- Enforce authorization, transaction limits, policy rules, and state transitions in deterministic services. The Policy/Compliance Agent is advisory and cannot waive a policy.
- Require explicit application or human approval for irreversible, financial, identity, case-closing, policy-exception, workforce, and external-communication actions.
- Fail closed on missing authorization and fail safe to clarification, text fallback, or human handoff on low grounding, repeated failure, safety concern, or required-tool outage.
- Prohibit autonomous adverse decisions based solely on sentiment, inferred vulnerability, accent, language, or other probabilistic attributes.

### Trace and log protection

Disable prompt, response, transcript, system-instruction, tool-definition, tool-argument/result, and evaluator-explanation capture by default. Record IDs, versions, timings, counts, outcomes, and error classes instead.

If sensitive generative-AI trace content is approved for a bounded troubleshooting purpose:

- use the dedicated Application Insights sensitive-content table behavior;
- set that table to protected/deny-by-default;
- grant only the Privileged Monitoring Data Reader role through time-bound access;
- apply short retention and audit every access;
- remove or redact secrets and prohibited data before export or support escalation.

## Options Considered

### Option A — Rely on model prompts and default filters

Rejected. Prompts are not authorization, consent, redaction, transaction, or retention controls, and default model filters do not cover every risk or intervention point.

### Option B — Layered privacy, zero-trust security, deterministic controls, and human oversight

Selected. It addresses the full data lifecycle and assumes every model, document, tool response, and network boundary can fail.

### Option C — Store complete calls centrally, then mask data for reports

Rejected. It maximizes breach impact, deletion scope, insider risk, and accidental model/trace disclosure. Restricted raw retention is purpose-specific and short.

### Option D — Never persist recordings or transcripts

Supported as a channel/policy mode and the safest default where mining is not approved. It cannot provide the full conversation-mining goal, so approved use cases may retain restricted artifacts under the controls above.

## Consequences

### Positive

- Reduces direct-identifier propagation and makes consent, purpose, retention, and deletion enforceable.
- Separates customer authorization and policy from probabilistic model behavior.
- Limits tool, prompt-injection, insider, trace, and cross-tenant blast radius.
- Creates measurable production gates for safety, fairness, privacy, and handoff.
- Gives operations a defensible record of controls and exceptions without declaring legal compliance prematurely.

### Negative

- Adds consent UX, redaction latency, restricted data zones, privileged-review workflows, deletion orchestration, key management, private networking, and continuous evaluation cost.
- Aggressive minimization can reduce troubleshooting and model-quality evidence.
- Redaction can remove context or miss PII; both false positives and false negatives require testing and exception handling.
- Private endpoints and identity support differ across Azure/Foundry/Fabric features, especially preview capabilities.
- Deletion may be asynchronous across indexes, analytical copies, soft-delete windows, and backups.

## Security and Governance Considerations

This ADR is the cross-cutting security decision for ADR-001 through ADR-006. Each implementation pull request must identify:

- data classes added or changed;
- purpose, lawful/consent basis, retention, residency, and deletion behavior;
- identities, roles, network paths, secrets, encryption, and audit events;
- model, prompt, retrieval, tool, and supply-chain threats;
- human oversight, fallback, and incident owner;
- tests and evidence required before deployment.

Maintain a data inventory, processing record, system/data-flow diagram, threat model, model and prompt inventory, tool registry, risk register, evaluation reports, access reviews, vendor/service terms, incident runbooks, and change approvals. Microsoft Purview can catalog and trace data, but governance ownership remains organizational.

## Observability and Evaluation

Security and Responsible-AI release gates include:

- PII redaction recall and residual leakage by entity class and locale;
- cross-tenant and document-level retrieval denial;
- direct and indirect prompt injection, jailbreak, data exfiltration, tool-confusion, and poisoned-content tests;
- harmful-content, groundedness, task-adherence, policy, hallucination, and citation results;
- tool selection/input validity, authorization denial, side-effect approval, and replay/idempotency;
- human-handoff availability, correctness, context minimization, and transfer failure;
- transcription and task performance across supported languages, accents, speech impairments, noise, devices, age groups where lawful to test, and channel quality;
- false-positive/false-negative disparity for sentiment, intent, compliance flags, and escalation;
- retention expiry, deletion completion, legal hold, key rotation, restore, and incident exercises.

Use offline evaluation before every model/prompt/tool/knowledge release, red-team high-risk paths, canary deployments, sampled continuous evaluation, drift monitoring, and periodic human review. Monitor guardrail interventions, denied tools, anomalous access/export, privileged trace access, prompt attacks, PII detections, deletion backlog, and safety-triggered handoffs without storing the prohibited content itself.

## Implementation Notes

1. Remove unconditional compliance claims and publish the approved purposes, limitations, and transparency notice.
2. Complete the data inventory, legal/privacy assessment, threat model, retention matrix, and responsibility assignment.
3. Replace plain SHA-256 examples with keyed pseudonymization and add deterministic plus conversational PII redaction.
4. Implement the consent state machine and nonrecorded/human fallback before persisting any real call.
5. Create production identities, Key Vault, private networking, RBAC/PIM, audit routing, and security alerts.
6. Implement restricted artifact storage, protected trace settings, retention, legal hold, and cross-store deletion.
7. Implement tool authorization, allow-listing, approval, Prompt Shields/guardrails, output validation, and safe handoff.
8. Build representative privacy, security, safety, fairness, accessibility, and recovery evaluation suites.
9. Obtain privacy, legal, security, Responsible-AI, operations, and business-owner approval before production.

Primary references:

- [Microsoft Foundry guardrails overview](https://learn.microsoft.com/azure/ai-foundry/guardrails/guardrails-overview)
- [Restrict access to sensitive Microsoft Foundry trace content](https://learn.microsoft.com/azure/ai-foundry/observability/how-to/traces-sensitive-content)
- [Conversation PII redaction](https://learn.microsoft.com/azure/ai-services/language-service/personally-identifiable-information/conversation-pii-overview)
- [Azure Communication Services call-recording responsibilities](https://learn.microsoft.com/azure/communication-services/concepts/voice-video-calling/call-recording)
- [Private networking for Foundry Agent Service](https://learn.microsoft.com/azure/ai-foundry/agents/how-to/virtual-networks)
- [Azure Cosmos DB security](https://learn.microsoft.com/azure/cosmos-db/security)
- [Microsoft Responsible AI Standard](https://www.microsoft.com/ai/responsible-ai)

## Open Questions

- Which countries, sectors, customer types, employee groups, and regulatory regimes are in scope?
- What are the approved purposes and legal/consent bases for transient processing, recording, transcription, mining, evaluation, and model improvement?
- Are payment, financial-advice, health, biometric, children, or other high-risk scenarios prohibited or separately controlled?
- What retention, legal-hold, backup-expiry, subject-access, correction, and deletion deadlines are binding?
- Which data and services may leave a country or region?
- Which preview services and public endpoints are acceptable under policy?
- What events require immediate human takeover, safety escalation, fraud escalation, or emergency handling?
- Who can reidentify a customer token, inspect unredacted content, confirm a policy finding, or approve a side effect?
- Which evaluator thresholds and disparity limits block release?
- Which teams are accountable for privacy, security operations, AI safety, records management, telecom compliance, and incident notification?
