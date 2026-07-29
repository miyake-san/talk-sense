# TalkSense Architecture Decision Records

This directory records the target architecture for evolving TalkSense from its current voice-agent analytics foundation into a Microsoft-based customer-service voice assistant and conversation-intelligence platform.

All decisions below are **Proposed**. They describe a target state; they do not indicate that the corresponding application, Azure, Foundry, or Fabric capabilities are deployed.

## Decision index

| ADR | Decision | Status | Primary scope |
| --- | --- | --- | --- |
| [ADR-001](./adr-001-microsoft-foundry-agent-architecture.md) | Adopt Microsoft Foundry Agent Architecture for TalkSense | Proposed | Conversation orchestrator and specialist agents |
| [ADR-002](./adr-002-microsoft-foundry-realtime-audio.md) | Add Voice Module with Microsoft Foundry Realtime Audio | Proposed | WebRTC, WebSocket, SIP, interruption, and handoff |
| [ADR-003](./adr-003-conversation-knowledge-mining-pipeline.md) | Conversation Knowledge Mining Pipeline | Proposed | Audio/transcript enrichment, persistence, and retrieval |
| [ADR-004](./adr-004-real-time-metrics-event-hubs-fabric.md) | Real-Time Metrics Architecture with Event Hubs and Microsoft Fabric | Proposed | Event contract, Eventstream, Eventhouse, and metrics |
| [ADR-005](./adr-005-fabric-ontology-data-agents.md) | Fabric Ontology and Fabric Data Agents for Operational Intelligence | Proposed | Domain semantics and natural-language analytics |
| [ADR-006](./adr-006-end-to-end-foundry-event-hub-fabric.md) | End-to-End Architecture: Microsoft Foundry + Event Hub + Fabric | Proposed | Overall boundaries, diagrams, and deployment |
| [ADR-007](./adr-007-security-privacy-responsible-ai.md) | Security, Privacy, Compliance, and Responsible AI | Proposed | Cross-cutting production controls |

See the [implementation roadmap](./implementation-roadmap.md) for assumptions, sequencing, and follow-up issues.

## Repository baseline

The decisions are grounded in the repository state on 2026-07-29:

- the implemented path is Voice Agent → Azure Event Hubs → Fabric Eventstream → Eventhouse/KQL → Power BI;
- Event Hubs infrastructure exists in Bicep and Terraform;
- Fabric Eventstream/Eventhouse configuration is documented but manual;
- the telemetry contract has four event types and the analytical model has five primary KQL tables;
- a PBIP/TMDL semantic model, report definition, sample data, and Python data generator exist;
- there is no customer frontend, backend API, voice/media module, Foundry agent, operational store, search index, mining pipeline, package manifest, automated test suite, or versioned CI workflow.

The Microsoft [Customer Chatbot Solution Accelerator](https://github.com/microsoft/customer-chatbot-solution-accelerator) informs the application and multi-agent plane. The [Conversation Knowledge Mining Solution Accelerator](https://github.com/microsoft/Conversation-Knowledge-Mining-Solution-Accelerator) informs the after-call enrichment and retrieval plane.

## Assumptions

- TalkSense will preserve its current Event Hubs/Fabric/Power BI analytical investment.
- The application implementation language and runtime have not been selected. React and Python/FastAPI are reference-accelerator patterns, not current repository conventions.
- The customer identity provider, CRM, case system, contact-center platform, carrier, PBX/SBC, and human-agent desktop are unknown.
- Browser WebRTC is the first voice prototype; SIP is the target contact-center integration.
- Cosmos DB is for operational conversation state, not the primary realtime analytical store.
- Raw audio and unredacted transcripts require explicit purpose, consent/legal approval, restricted storage, and short retention.
- Microsoft feature status, regional availability, quotas, network support, licensing, and API versions must be revalidated before implementation. Fabric Ontology is treated as preview.
- No production compliance claim is made until organizational privacy, legal, security, Responsible-AI, records, and operations reviews approve the implementation.

## Decision relationships

- ADR-006 selects the overall hybrid architecture and incorporates ADR-001 through ADR-005.
- ADR-007 applies to every other ADR and can block their production adoption.
- ADR-001 defines the agents used by ADR-002, ADR-003, and ADR-005.
- ADR-004 is the asynchronous bridge between the application/AI plane and Fabric.
- ADR-003 supplies enriched data to ADR-004 and ADR-005.
- ADR-005 consumes the governed realtime and historical products produced by ADR-003 and ADR-004.

## ADR lifecycle

Use these statuses:

- **Proposed** — under review and not yet an implementation commitment;
- **Accepted** — approved for implementation;
- **Rejected** — evaluated but not selected;
- **Superseded** — replaced by a later ADR, with a link to the replacement;
- **Deprecated** — still present but no longer recommended.

When accepting an ADR, record approvers and any conditions in the ADR. When architecture changes, add or supersede a decision rather than silently changing an accepted rationale.

## Identifier migration

The repository previously used ADR-001 for a Cosmos DB analytics decision and ADR-002 for the Event Hubs/Fabric RTI decision. The required target decision set also assigns ADR-001 and ADR-002. Those active identifiers were reassigned:

- the useful Cosmos DB decision is narrowed to operational conversation state in ADR-003 and ADR-006;
- the Event Hubs → Eventstream → Eventhouse decision is preserved and expanded in ADR-004 and ADR-006.

The displaced files remain available in Git history. All current documentation should link to this index or to the replacement ADRs.
