# ADR-001 — Adopt Microsoft Foundry Agent Architecture for TalkSense

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

TalkSense currently implements an analytics plane, not a customer-facing chatbot runtime. The repository contains:

- Azure Event Hubs infrastructure in Bicep and Terraform;
- a documented JSON telemetry contract;
- manual configuration for Fabric Eventstream and Eventhouse/KQL;
- a Power BI semantic model and report;
- Python synthetic-data generation.

There is no frontend, backend API, conversational runtime, agent definition, retrieval service, operational conversation store, package manifest, automated test suite, or CI workflow in the repository. Any application stack described here is therefore a target architecture and not an extension of existing application code.

The [Customer Chatbot Solution Accelerator](https://github.com/microsoft/customer-chatbot-solution-accelerator) provides the closest Microsoft reference for the missing application plane. Its relevant patterns are a React scenario host and embeddable chat experience, API backends, a Microsoft Foundry orchestrator, specialist agents exposed as tools, grounded enterprise knowledge, and Cosmos DB conversation history. TalkSense already has an Event Hubs and Fabric analytics plane that the accelerator does not provide.

| Capability | TalkSense today | Customer Chatbot accelerator pattern | Target for TalkSense |
| --- | --- | --- | --- |
| Customer channel | Not present | Web application and embeddable chat | Web/text first, then browser voice and SIP |
| Application API | Not present | API services | Channel/session API and secure tool gateway |
| Orchestration | Not present | Foundry orchestrator with specialist agents | Microsoft Agent Framework orchestrator hosted through Foundry Agent Service |
| Knowledge | Not present | Foundry IQ/Azure AI Search | Permission-aware Foundry IQ knowledge base, with Azure AI Search as the retrieval engine/fallback |
| Session history | Design only in the displaced database ADR | Cosmos DB | Cosmos DB operational state with explicit retention |
| Voice | Not present | Voice-enabled reference patterns | Realtime audio transport defined by ADR-002 |
| Analytics | Event Hubs, Fabric RTI, Power BI | Primarily application telemetry | Preserve and extend the existing TalkSense analytics plane |

Microsoft Foundry Agent Service is the managed control and runtime plane for agent identities, versions, tools, tracing, and evaluation. Microsoft Agent Framework is the application SDK for custom orchestration. These are complementary: TalkSense will use Agent Framework for orchestration logic and deploy that logic as a hosted agent when the required hosting, region, network, and protocol capabilities are validated.

## Decision

Adopt a multi-agent architecture with one customer-facing **Conversation Orchestrator** and five bounded specialist agents. The orchestrator owns the conversation turn and exposes specialists as typed tools. It must not delegate authorization or irreversible decisions to a language model.

### Agent responsibilities

| Agent | Responsibility | Execution path |
| --- | --- | --- |
| **Conversation Orchestrator** | Maintain turn context, choose approved tools, compose grounded responses, manage latency budgets, and initiate handoff | Synchronous customer path |
| **Knowledge Agent** | Retrieve product, procedure, troubleshooting, and case knowledge with citations and caller-specific access filters | Synchronous, read-only |
| **Policy/Compliance Agent** | Explain approved policies and identify possible policy or compliance conflicts | Synchronous advisory path; deterministic policy services remain authoritative |
| **Escalation Agent** | Collect escalation reason, prepare a structured handoff package, select an eligible queue, and request transfer | Synchronous; every side effect is reauthorized by the application |
| **Conversation Mining Agent** | Enrich completed calls with summaries, topics, sentiment, entities, relationships, actions, and flags | Asynchronous after-call path |
| **Metrics Agent** | Answer governed operational questions through Fabric Data Agents or parameterized KQL/semantic-model tools | Read-only analyst path; excluded from the customer latency-critical path |

### Orchestration boundaries

1. The application runtime authenticates the caller or establishes an anonymous session, captures consent, creates a correlation context, and opens the audio or text session.
2. The Conversation Orchestrator receives only the minimum turn context needed for the task.
3. Specialist agents are invoked through versioned, allow-listed tool contracts with JSON-schema validation, timeouts, bounded retries, and explicit failure results.
4. Knowledge and policy results include source identifiers and citations. A generated answer without sufficient grounding must ask a clarifying question, provide a safe fallback, or hand off.
5. The application, not the model, checks customer authorization, policy constraints, queue eligibility, and approval requirements before any case update, transaction, or call transfer.
6. Realtime events are projected to Event Hubs without raw audio, secrets, or unredacted transcript content.
7. Conversation mining runs from a durable after-call work queue. It does not block the voice response loop.

The initial release should use one orchestrator plus the Knowledge, Policy/Compliance, and Escalation agents. Conversation Mining and Metrics become separate agents only when their asynchronous data products and governed tools exist. This avoids creating nominal agents with overlapping prompts and no enforceable boundary.

## Options Considered

### Option A — One monolithic conversational agent

Rejected as the target. It is simple for a prototype but combines customer dialogue, retrieval, policy interpretation, side effects, analytics, and escalation in one prompt and identity. That increases prompt complexity, tool privilege, blast radius, and evaluation scope.

### Option B — Orchestrator with bounded specialist agents

Selected. It matches the Customer Chatbot accelerator, permits independent instructions and evaluations, and supports least-privilege tool access. It adds orchestration latency and operational complexity, so only specialists with a distinct data or authority boundary will be created.

### Option C — Application code orchestrates direct model calls without Agent Service

Retained as a fallback for the first proof of concept or where hosted-agent features are unavailable. It offers maximum protocol control, but TalkSense would have to own agent versioning, identity, tracing, tool governance, and lifecycle management.

### Option D — Fabric Data Agent as the customer-facing orchestrator

Rejected. Fabric Data Agents are intended for read-only questions over governed analytical data. They are not a low-latency voice runtime, transaction coordinator, or customer authorization boundary.

## Consequences

### Positive

- Separates customer experience, knowledge, compliance, escalation, mining, and analytics concerns.
- Reuses the existing Event Hubs/Fabric investment without placing Fabric in the realtime response loop.
- Allows agent-specific identities, tools, prompts, release cadence, and evaluation datasets.
- Makes human handoff and safe degradation explicit capabilities rather than prompt-only behavior.
- Aligns the new application plane with a maintained Microsoft reference architecture.

### Negative

- Adds network calls, failure modes, version compatibility, and trace correlation across agents.
- Requires a new application runtime, operational database, knowledge ingestion pipeline, and deployment lifecycle that do not exist in this repository.
- Multi-agent calls can increase latency and token consumption. Tool and agent fan-out must be bounded.
- Some Foundry hosting, guardrail, Fabric-tool, tracing, and network-isolation capabilities may be preview or region-dependent.

### Neutral or transitional

- The Customer Chatbot accelerator's React and Python/FastAPI choices are references, not repository conventions. The implementation stack requires a separate decision because TalkSense has no current frontend/backend language.
- The former ADR-001 Cosmos DB decision is incorporated as operational conversation state in ADR-003 and ADR-006. Its historical text remains available in Git history.

## Security and Governance Considerations

- Give each runtime and specialist a dedicated managed identity and the minimum data-plane roles required for its tools.
- Keep credentials out of prompts, model context, traces, and tool responses. Store unavoidable secrets in Azure Key Vault.
- Expose only approved tools. Validate inputs and outputs, enforce tenant and user authorization in application code, and treat every retrieved document and tool result as untrusted input.
- Separate read-only tools from side-effecting tools. Require application approval or human approval for financial, account, policy-exception, case-closing, and transfer actions.
- Apply Microsoft Foundry guardrails to user input, tool calls, tool responses, and output where supported. Add application controls where a risk or audio model is not covered.
- Enforce retrieval access control and document-level permissions in Foundry IQ/Azure AI Search. Never rely on prompt instructions to hide unauthorized knowledge.
- Redact or tokenize PII before sending conversation data to Event Hubs, Fabric, search indexes, or standard traces, as defined in ADR-007.
- Version agent instructions, models, tool schemas, knowledge indexes, and policy bundles as one release manifest so a response can be reproduced.

## Observability and Evaluation

Use one W3C `traceparent` across channel, session API, realtime model, orchestrator, specialist, tool, Event Hubs, and mining operations. Application Insights and Log Analytics are the operational diagnostic system; Eventhouse is the business and conversation analytics system.

At minimum, capture:

- agent and prompt version, model deployment, tool name/version, and knowledge-index version;
- per-agent and end-to-end latency, time to first audio, tokens, retries, throttling, cancellation, and failures;
- tool selection, valid input, execution success, citation coverage, grounding, and handoff outcome;
- containment, repeat-contact proxy, escalation, policy flags, and customer feedback;
- safety interventions and denied tool calls without retaining prohibited content.

Maintain offline, predeployment, canary, and sampled production evaluations. Evaluation sets must cover task completion, intent resolution, groundedness, citation correctness, policy adherence, tool selection/input, handoff correctness, safety, PII leakage, Portuguese and other supported locales, accents, and noisy audio. Human reviewers own release thresholds for high-risk scenarios.

## Implementation Notes

1. Add an application plane without changing the existing analytics contract first: a channel/session API, a text client, and a secure tool gateway.
2. Establish a Foundry project per environment and connect it to Application Insights.
3. Implement the Conversation Orchestrator with a small allow-list of read-only tools before adding side effects.
4. Ingest a curated knowledge corpus into Azure AI Search and expose it through Foundry IQ when its regional and feature requirements are satisfied.
5. Add Policy/Compliance as an advisory agent backed by versioned policy documents and deterministic policy checks.
6. Add structured human handoff before adding autonomous case mutation.
7. Integrate the Event Hubs projection defined in ADR-004.
8. Add the asynchronous Conversation Mining Agent after ADR-003 storage and redaction controls exist.
9. Add the Metrics Agent only after the Fabric ontology, Data Agents, identity model, and answer evaluation in ADR-005 are operational.

Primary references:

- [Customer Chatbot Solution Accelerator](https://github.com/microsoft/customer-chatbot-solution-accelerator)
- [Microsoft Foundry Agent Service overview](https://learn.microsoft.com/azure/foundry/agents/overview)
- [Microsoft Agent Framework overview](https://learn.microsoft.com/agent-framework/overview/agent-framework-overview)
- [Tool best practices for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/concepts/tool-best-practice)
- [Foundry IQ overview](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)

## Open Questions

- Which frontend and backend languages will become TalkSense conventions?
- Which Foundry agent hosting model and regions satisfy the latency, data residency, private networking, and support requirements?
- Which customer identity provider, CRM, case-management system, and contact-center platform must be integrated?
- Which actions can be autonomous, which require deterministic approval, and which always require a human?
- What are the per-channel latency and availability service-level objectives?
- Can specialist-agent calls meet the voice latency budget, or should some specialists be deterministic in-process services?
- Is Foundry IQ available for the required regions and document-level authorization model, or must the first release use Azure AI Search directly?
- Who owns prompts, policy content, knowledge quality, agent evaluations, and production release approval?
