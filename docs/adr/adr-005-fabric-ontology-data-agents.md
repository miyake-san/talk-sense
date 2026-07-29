# ADR-005 — Fabric Ontology and Fabric Data Agents for Operational Intelligence

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

TalkSense currently exposes a physical analytics model: Eventhouse tables, a Power BI star schema, Portuguese business labels, and DAX measures for nine call-center metrics. Business meaning is distributed across documentation, KQL examples, TMDL, and report visuals. There is no machine-readable domain model connecting customers, conversations, intents, cases, products, policies, escalations, agents, events, metrics, and service levels.

Microsoft Fabric provides two distinct capabilities:

- **Fabric IQ/Fabric Ontology** models business entities, properties, relationships, and source bindings. Fabric Ontology remains a preview capability as of this ADR date and must not become a production security or availability dependency until approved.
- **Fabric Data Agents** provide governed, read-only natural-language access to supported Fabric sources such as Eventhouse/KQL, Lakehouse/Warehouse SQL endpoints, Power BI semantic models, and—subject to feature status—ontology. A data agent is not the same as Foundry IQ, the retrieval layer used by customer-facing Foundry agents.

The target must answer both realtime operational questions and historical business questions without exposing raw table names or requiring users to write KQL, SQL, or DAX.

## Decision

Create a versioned support-domain ontology over approved realtime and historical data products, and create two narrowly scoped Fabric Data Agents:

1. **TalkSense Operations Data Agent** for current and near-realtime call, voice, agent, tool, escalation, and error metrics in Eventhouse.
2. **TalkSense Business Intelligence Data Agent** for governed historical trends, certified measures, customer segments, products, cases, policies, and SLA analysis through the Lakehouse/OneLake and Power BI semantic model.

The Metrics Agent in ADR-001 may invoke these data agents as read-only tools after identity propagation, query controls, and answer evaluation are proven. Business users may also use the Fabric-native experience. The customer-facing Conversation Orchestrator must not query broad operational analytics in its latency-critical path.

### Domain ontology

| Entity | Core properties | Primary analytical binding |
| --- | --- | --- |
| **Customer** | `customerIdAnon`, tenant, segment, region, consent/retention class | Curated `DimCustomer`; never direct identifiers |
| **Call** | call ID, channel, start/end, duration, locale, codec, quality summary | Eventhouse `Conversations`/`VoiceQuality`; historical `FactCall` |
| **Conversation** | conversation ID, outcome, containment, sentiment, summary reference | Eventhouse `Conversations`; historical `FactConversation` |
| **Intent** | intent ID, taxonomy version, name, category | Curated `DimIntent`, turn aggregates |
| **Topic** | topic ID, taxonomy/model version, name, confidence | Mining output and `DimTopic` |
| **Agent** | AI agent ID, role, version, model deployment | `AgentInvocations`, `DimAgent` |
| **HumanAgent** | pseudonymous workforce ID, team, skill group | Approved workforce dimension and handoff facts |
| **Case** | case ID/token, type, status, priority, resolution | Curated CRM/case data |
| **Product** | product ID, family, version, status | Approved product dimension |
| **Policy** | policy ID, version, jurisdiction, effective dates | Policy catalog and `PolicyFindings` |
| **Escalation** | escalation ID, reason, queue, status, wait and transfer outcome | Eventhouse `Escalations` and historical fact |
| **Metric** | metric ID, name, definition version, value, grain, unit | Certified KQL functions and semantic-model measures |
| **SLA** | SLA ID, target, threshold, population, effective dates | Curated SLA dimension |
| **Event** | event ID, type, time, source, outcome, schema version | Eventhouse `RawTelemetry`/typed event tables |

### Relationships

- A **Customer** participates in zero or more **Conversations**.
- A **Conversation** comprises one or more **Calls** or channel sessions and emits **Events**.
- A **Conversation** has primary and secondary **Intents**, discusses **Topics** and **Products**, and can open or update a **Case**.
- A **Conversation** is handled by an AI **Agent**, may be transferred to a **HumanAgent**, and may create an **Escalation**.
- An **Agent** invocation and a **Conversation** are governed by effective **Policies**.
- A **Policy** can be associated with candidate or confirmed findings on a **Conversation** or **Event**.
- A **Metric** observes an entity or relationship at a declared grain and is measured against an effective **SLA**.
- A **Case** can relate multiple Conversations, enabling repeat-contact and first-contact-resolution analysis without exposing direct identity.

Every entity binding includes a stable key, tenant key, source, source version, effective time, and freshness. Relationships across stores use pseudonymous, scoped identifiers. Ontology definitions do not copy raw transcript or audio content.

### Realtime and historical bindings

Use a medallion-style boundary:

- **Eventhouse/KQL realtime bindings:** `Conversations`, `Turns`, `Events`, `VoiceQuality`, `AgentInvocations`, `ToolCalls`, `Escalations`, `ModelUsage`, `PolicyFindings`, `Evaluations`, and `CSAT`.
- **OneLake/Lakehouse historical bindings:** conformed customer, date, intent, topic, AI-agent, human-agent, product, policy, and SLA dimensions; conversation/call/case/escalation/metric facts; and bridge tables for many-to-many relationships.
- **Power BI semantic model:** certified business measures, denominator rules, hierarchies, localization, and RLS/OLS used for historical business reporting.

KQL functions provide the realtime version of certified metrics. The semantic model provides the historical version. Both reference one metric-definition catalog and are reconciled; the ontology describes these definitions but is not a third calculation engine.

### Data Agent scopes

The Operations Data Agent receives:

- only the Eventhouse databases/tables/functions needed for operational questions;
- descriptions of event-time versus ingestion-time behavior;
- certified KQL examples for latency, containment, escalation, audio quality, failures, tool calls, and token usage;
- freshness and partial-data rules;
- instructions to aggregate by default and refuse direct customer-level disclosure without an authorized use.

The Business Intelligence Data Agent receives:

- the certified Power BI semantic model and, where required, curated Lakehouse SQL tables;
- business synonyms in Portuguese and English;
- certified measures and cohort/denominator definitions;
- instructions for temporal comparison, confidence, suppression of small groups, and source citation;
- ontology binding only after the preview capability passes governance and reliability gates.

Do not attach raw files, unrestricted transcript stores, or more data sources than necessary. As of this ADR date, a Fabric Data Agent can combine up to five supported data sources; that limit and each source's feature status must be revalidated at implementation time.

### Example questions

Business users should be able to ask:

- “What is the containment rate in the last 30 minutes, and how does it compare with the same period last week?”
- “Which intents have the highest p95 time to first audio today?”
- “Did packet loss or reconnects increase before the escalation spike?”
- “Which tool and model versions account for the most caller-visible errors?”
- “How many callers requested an agent versus how many transfers completed?”
- “Which queues are breaching transfer-wait SLA right now?”
- “What are the top new topics this week that are not represented in the current intent taxonomy?”
- “Which products have the largest month-over-month increase in repeat-contact proxy?”
- “Show confirmed policy findings by policy version and product, excluding pending review.”
- “How did containment, average handle time, and CSAT change after agent version 2.3?”
- “Which customer segments have low satisfaction proxy but no completed CSAT survey?”
- “What percentage of mined conversations missed the processing-completion objective?”

Answers include the time range, freshness, filters, denominator, units, metric-definition version, source, and generated KQL/SQL/DAX where the user is authorized to inspect it. A satisfaction proxy is never presented as NPS.

## Options Considered

### Option A — Let each Data Agent infer meaning from physical schemas

Rejected as the target. It is quick to demonstrate but produces inconsistent business definitions and fragile natural-language-to-query behavior.

### Option B — Fabric ontology plus two scoped Data Agents

Selected, subject to preview exit gates for ontology. It establishes shared business language while separating realtime operational access from historical business access.

### Option C — One broad Data Agent over every source

Rejected initially. Although a single interface is attractive, broad source access increases ambiguity, cross-source query failures, latency, permission complexity, and accidental disclosure. A governed Foundry Metrics Agent can route to two scoped agents.

### Option D — Custom Metrics Agent with hand-written KQL/SQL tools only

Retained as the production fallback while ontology or a Data Agent source is preview, unavailable, or insufficiently accurate. Parameterized tools provide greater determinism at the cost of coverage and maintenance.

### Option E — Power BI Q&A only

Rejected as the full solution. It can answer semantic-model questions but does not cover realtime Eventhouse operations, ontology relationships, agent-tool telemetry, or a Foundry tool interface.

## Consequences

### Positive

- Gives business users a shared vocabulary independent of KQL table and column names.
- Connects existing realtime and Power BI investments rather than replacing them.
- Supports governed natural-language analysis over realtime and historical data.
- Makes metric definitions, source freshness, relationships, and ownership explicit.
- Allows the Metrics Agent to remain read-only and outside the customer voice path.

### Negative

- Ontology is preview and can change in feature set, API, deployment, and licensing.
- Two agents need synchronized terminology, measures, security rules, and evaluation.
- Natural-language-to-query can generate valid but semantically incorrect queries.
- Cross-source questions can have different freshness, grain, timezone, and security semantics.
- Ontology and data-agent configuration add release artifacts that need source control and environment promotion.

## Security and Governance Considerations

- Treat ontology and Data Agents as semantic/query layers, not authorization boundaries. Enforce access in each source and verify identity propagation at query time.
- Separate Fabric workspaces and identities by environment. Use least-privilege item permissions and do not grant broad workspace access merely to enable an agent.
- Apply KQL database/table policies for direct KQL access and RLS/OLS in the Power BI semantic model. Confirm how OneLake security applies independently.
- Bind only pseudonymized customer and workforce identifiers. Direct PII and raw transcript content remain outside the ontology.
- Apply Microsoft Purview cataloging, lineage, ownership, sensitivity labels, DLP, audit, and endorsed/certified status to source items and semantic models.
- Suppress or refuse small-group, individual-performance, and sensitive-segment results according to approved policy.
- Log the user identity, agent/version, generated query hash or approved query text, sources, result size, duration, and policy decision. Do not duplicate sensitive result rows in logs.
- Data Agents are read-only. Any write, case update, workforce action, or customer decision requires a separate authorized application workflow and human approval where required.

## Observability and Evaluation

Create a versioned golden question set for each agent with:

- expected source, query pattern, filters, grain, metric, and answer;
- acceptable numerical tolerance and freshness;
- allowed and denied identities;
- adversarial ambiguity, prompt injection, unsupported joins, and data-exfiltration cases;
- Portuguese and English paraphrases.

Measure query-generation success, execution success, semantic correctness, numerical accuracy, source selection, answer completeness, freshness disclosure, latency, refusal correctness, and user feedback. Reconcile realtime KQL and historical semantic-model results for overlapping closed periods. Re-run evaluations whenever schemas, ontology, measures, instructions, permissions, or Fabric runtime versions change.

Monitor Data Agent usage, failed or expensive queries, throttling, source errors, result-size anomalies, authorization denials, stale bindings, and ontology deployment drift.

## Implementation Notes

1. Create a domain glossary and metric-definition catalog from the current data dictionary, KQL, and TMDL before creating the ontology.
2. Add stable IDs, tenant keys, effective dates, provenance, and version columns to curated source tables.
3. Implement and test certified KQL functions for realtime metrics.
4. Align the Power BI semantic model with the same definitions and add required dimensions/relationships.
5. Create the Operations Data Agent over Eventhouse and validate a small golden set.
6. Create the Business Intelligence Data Agent over the semantic model and curated Lakehouse data.
7. Prototype the ontology in a nonproduction Fabric workspace, bind entities incrementally, and set explicit preview exit criteria.
8. Connect the agents to the ADR-001 Metrics Agent only after source authorization and answer-quality gates pass.
9. Publish business-user guidance describing intended questions, freshness, limitations, and escalation for incorrect answers.

Primary references:

- [What is Fabric IQ?](https://learn.microsoft.com/fabric/iq/overview)
- [Fabric Ontology overview](https://learn.microsoft.com/fabric/iq/ontology/overview)
- [Fabric Ontology agent integration](https://learn.microsoft.com/fabric/iq/ontology/concepts-agent-integration)
- [Fabric Data Agent overview](https://learn.microsoft.com/fabric/data-science/concept-data-agent)
- [Add data sources to a Fabric Data Agent](https://learn.microsoft.com/fabric/data-science/data-agent-add-datasources)
- [Fabric Data Agent governance and security](https://learn.microsoft.com/fabric/data-science/concept-data-agent#governance-and-security)

## Open Questions

- What is the production status, regional availability, API stability, and licensing of Fabric Ontology at implementation time?
- Which Data Agent sources and identity-propagation modes are generally available in the target Fabric region/capacity?
- Are Eventhouse and the semantic model sufficient, or is a Lakehouse SQL endpoint needed as a third source?
- Which team owns the glossary, ontology, metric definitions, synonyms, and certification workflow?
- Which individual-level and small-cohort questions must be denied or masked?
- How accurately do Data Agents interpret Portuguese business terminology and follow-up questions?
- What is the allowed freshness difference between realtime and historical answers?
- How are ontology and Data Agent definitions exported, reviewed, promoted, rolled back, and recovered?
- What fallback experience is required if an ontology or Data Agent capability changes or becomes unavailable?
