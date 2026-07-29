# ADR-003 — Conversation Knowledge Mining Pipeline

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

TalkSense currently accepts analytics labels produced by an external voice agent, including intent, sentiment, latency, outcome, and event type. It does not ingest recordings, transcribe audio, enrich conversations, generate embeddings, or provide semantic retrieval over transcripts. The data model mentions recording and transcript-oriented fields, but no storage or processing implementation exists.

The [Conversation Knowledge Mining Solution Accelerator](https://github.com/microsoft/Conversation-Knowledge-Mining-Solution-Accelerator) demonstrates a complementary pattern:

- audio and transcripts arrive through durable object storage and a work queue;
- Azure AI Content Understanding and Azure OpenAI extract structured insights;
- metadata and operational state are stored separately from searchable chunks;
- Azure AI Search supports semantic/vector retrieval;
- a Foundry agent reasons across structured analytics and retrieved conversation evidence.

TalkSense has a stronger realtime analytics foundation than the accelerator, while the accelerator has the after-call content pipeline TalkSense lacks. Event Hubs should continue to carry small analytics events; it is not the system of record for recordings or a durable job queue.

## Decision

Add an asynchronous, idempotent conversation-mining pipeline based on the accelerator pattern. Process permitted recordings and transcripts with Azure AI Content Understanding, Azure OpenAI, Azure AI Language conversational PII redaction, and Foundry IQ/Azure AI Search. Keep restricted source artifacts, operational conversation state, searchable knowledge, and analytical facts in separate stores.

### Processing flow

1. **Finalize the call artifact.** After consent and call completion, store the encrypted recording and live transcript in a restricted Blob Storage/ADLS Gen2 landing zone. Write immutable metadata containing `tenantId`, `conversationId`, source channel, locale, consent policy/version, content hash, and retention class.
2. **Create durable work.** Publish a storage event to Event Grid and a durable queue such as Azure Service Bus. Use `conversationId`, content hash, and pipeline version as the idempotency key. Event Hubs remains the analytics stream, not the work queue.
3. **Analyze audio.** Run an Azure AI Content Understanding audio analyzer. Start from `prebuilt-callCenter` where available, then create a custom analyzer for TalkSense fields. Capture transcript text, speaker/role attribution, timestamps, segment confidence, language, summary candidates, sentiment, topics, and other configured fields.
4. **Normalize.** Convert live and after-call transcripts into a canonical ordered-turn schema. Preserve provenance and confidence for every derived value. Keep the original restricted output for audit only when retention policy permits.
5. **Redact and tokenize.** Run Azure AI Language Conversation PII on the canonical transcript. Replace direct identifiers with typed placeholders or stable, scoped tokens. Do not publish unredacted text to Event Hubs, Fabric, search, standard application logs, or unrestricted traces.
6. **Enrich.** Use a versioned Azure OpenAI structured-output workflow over the redacted transcript to extract the approved domain schema. Validate JSON against the schema and retry only bounded, retryable failures.
7. **Validate flags.** Treat model-produced compliance findings as candidates. Apply deterministic policy rules and route high-risk or low-confidence findings to authorized human review before labeling a confirmed violation.
8. **Index knowledge.** Chunk by speaker turn and semantic section while retaining conversation, time, topic, policy, product, and access metadata. Generate embeddings and index only redacted text in Azure AI Search. Expose the index through Foundry IQ when supported for the selected region and permission model.
9. **Persist and publish.** Store operational history and the latest enrichment state in Cosmos DB, publish normalized analytical facts to Event Hubs, and materialize historical curated tables in OneLake/Lakehouse. Store references, not recordings, in downstream systems.
10. **Delete consistently.** A deletion workflow removes or tombstones all permitted copies in Blob/ADLS, Cosmos DB, Azure AI Search, Eventhouse, OneLake, caches, and derived exports, subject to legal hold and service backup constraints.

### Extraction contract

The enrichment schema will include:

- call reason, primary and secondary intents, discovered topics, and key phrases;
- conversation, customer, and human-agent sentiment with trend and confidence;
- named entities and typed relationships between customer, product, case, policy, issue, and action;
- concise customer-facing and human-agent handoff summaries;
- decisions made, troubleshooting steps, commitments, action items, owner, and due date;
- products, features, defects, competitor mentions, and root-cause candidates;
- escalation reason, outcome, containment, first-contact-resolution proxy, and repeat-contact link;
- candidate compliance flags with policy reference, evidence span, severity, confidence, and review status;
- language, speaker/role, timestamps, silence, overlap, interruption, and audio-quality indicators where available.

Every derived field includes `sourceArtifactId`, `sourceSpan` or timestamps where possible, `analyzerVersion`, `modelDeployment`, `promptVersion`, `taxonomyVersion`, `processingRunId`, confidence, and creation time. Unsupported or uncertain values are `null`; the pipeline must not invent a value to satisfy a required field.

### Persistence strategy

| Data product | System of record | Access and purpose |
| --- | --- | --- |
| Raw recording and unredacted analyzer output | Restricted Blob Storage/ADLS Gen2 | Short-retention replay, dispute, and approved review only |
| Canonical unredacted transcript | Restricted Blob/ADLS or disabled entirely by policy | Separate privileged access; never an analytics source |
| Operational session and redacted conversation history | Azure Cosmos DB for NoSQL | Low-latency session continuity, processing status, handoff summary, deletion state |
| Redacted chunks and embeddings | Azure AI Search, exposed through Foundry IQ where applicable | Permission-aware hybrid/vector retrieval with citations |
| Realtime facts and quality events | Eventhouse/KQL through ADR-004 | Operational metrics and near-realtime analysis |
| Curated historical entities and relationships | Fabric Lakehouse/OneLake | Long-term trends, ontology binding, semantic models, approved data science |
| Agent/model diagnostics | Application Insights/Log Analytics | Restricted operational troubleshooting, not business reporting |

Use a hierarchical Cosmos DB partition key such as tenant plus conversation where supported, or a synthetic tenant-conversation key after workload testing. Store large audio and transcript bodies outside Cosmos DB. Use Cosmos DB TTL for operational history and change feed only where a specific downstream process requires it.

The former ADR-001 selected Cosmos DB as an analytics database. This ADR narrows Cosmos DB to operational conversation and pipeline state. Eventhouse remains the realtime analytical store, and OneLake/Lakehouse remains the curated historical analytical store.

## Options Considered

### Option A — Trust only the voice agent's live intent and sentiment

Rejected as the target. It is inexpensive and already represented by the schema, but it cannot independently verify the call, recover missed fields, perform conversation-wide analysis, or support semantic retrieval and evidence-based review.

### Option B — Asynchronous Content Understanding plus Azure OpenAI pipeline

Selected. It separates the latency-critical conversation from richer post-call analysis and follows the Conversation Knowledge Mining accelerator. It adds processing delay, model cost, versioning, and additional stores.

### Option C — Run full content analysis on every streaming turn

Rejected for the initial architecture. It increases voice latency and cost, produces partial-context conclusions, and complicates redaction. A small set of realtime safety or escalation classifiers may run in the hot path, but full mining remains asynchronous.

### Option D — Store and query transcripts only in Eventhouse

Rejected. KQL is appropriate for events and aggregations, but it is not the preferred system of record for recordings, operational session state, document-level retrieval ACLs, or vectorized knowledge chunks.

### Option E — Use Azure AI Search directly without Foundry IQ

Accepted as a deployment fallback. Azure AI Search remains the underlying retrieval service and gives explicit index/query control. Foundry IQ is preferred when its managed knowledge, permission, citation, and agentic-retrieval capabilities meet the regional and governance requirements.

## Consequences

### Positive

- Produces reproducible, conversation-wide insights independently of the live voice agent.
- Enables evidence-linked summaries, compliance review, semantic search, and grounded agents.
- Keeps expensive mining out of the realtime audio loop.
- Separates stores according to workload and data sensitivity.
- Reuses existing Event Hubs, Eventhouse, OneLake, and Power BI assets through normalized outputs.

### Negative

- Introduces Blob/ADLS, a durable queue, Content Understanding, Azure AI Language, Azure OpenAI, Cosmos DB, and Azure AI Search operational responsibilities.
- The same conversation can have live labels and post-call labels that disagree; consumers need provenance and precedence rules.
- Reprocessing after analyzer, model, prompt, taxonomy, or redaction changes creates multiple versions.
- PII redaction and machine extraction are probabilistic and require measured residual-risk controls.
- Search deletion, backups, legal holds, and OneLake-derived copies make subject deletion a cross-system workflow.

## Security and Governance Considerations

- Do not create or retain a recording without an applicable consent and lawful-purpose decision.
- Place raw artifacts in a dedicated restricted account/container with private endpoints, managed identity, malware scanning, encryption, no public access, and narrowly scoped privileged roles.
- Redact before indexing or analytics publication. Preserve offsets and typed placeholders so evidence remains usable without revealing identifiers.
- Replace the current plain-hash assumption for customer identifiers with a keyed, rotated pseudonymization service as defined in ADR-007.
- Apply tenant, case, geography, legal-hold, and user/group ACL metadata to every search document. Test that retrieval filters fail closed.
- Do not put embeddings of unredacted text into the index; embeddings can leak semantic information and are in scope for deletion.
- Separate candidate compliance flags from confirmed findings. Restrict evidence and reviewer identity, and audit changes to disposition.
- Use managed identities and least-privilege roles between every stage. Use Key Vault for non-identity secrets and customer-managed keys only where the compliance requirement justifies their lifecycle overhead.
- Prevent prompt injection in transcripts and attached content by treating source text as data, constraining the extraction schema, disabling unnecessary tools, and validating all output.

## Observability and Evaluation

Track queue age, stage duration, retries, throttling, dead letters, idempotent skips, artifact size/duration, analyzer failures, redaction coverage, JSON validation failures, indexing lag, deletion completion, and end-to-end processing latency.

Maintain labeled evaluation sets stratified by locale, channel, product, call reason, duration, speaker count, noise, accent, and risk class. Measure:

- word/segment error, diarization and speaker-role accuracy;
- intent/topic classification precision, recall, and taxonomy coverage;
- entity and relationship precision/recall;
- summary factuality, completeness, evidence alignment, and action-item accuracy;
- sentiment agreement and calibration;
- compliance-flag false-positive/false-negative rates by policy;
- PII detection recall by entity category and residual leakage;
- retrieval recall, ranking quality, permission-filter correctness, and citation validity.

Never make analyzer confidence the sole release criterion. Compare against human-reviewed ground truth and define higher thresholds for adverse, compliance, financial, or account-impacting uses.

## Implementation Notes

1. Define the canonical transcript, enrichment, evidence, and processing-run schemas before provisioning the pipeline.
2. Run the first slice on synthetic and explicitly approved recordings; validate supported locales, duration/size limits, regions, and quotas.
3. Implement consent metadata, restricted landing storage, queue, idempotency, and deletion before bulk ingestion.
4. Start with Content Understanding transcription/diarization plus a small custom schema.
5. Add conversational PII redaction and verify offsets across multi-speaker turns.
6. Add Azure OpenAI structured extraction for summaries, topics, entities, relationships, actions, and candidate compliance flags.
7. Add Cosmos operational state and the redacted Azure AI Search index.
8. Emit enrichment-completed and quality events through ADR-004, then add OneLake curated tables and ADR-005 ontology bindings.
9. Establish a controlled reprocessing process that preserves prior versions and prevents duplicate downstream facts.

Primary references:

- [Conversation Knowledge Mining Solution Accelerator](https://github.com/microsoft/Conversation-Knowledge-Mining-Solution-Accelerator)
- [Unlock insights from conversational data](https://learn.microsoft.com/azure/architecture/ai-ml/idea/unlock-insights-from-conversational-data)
- [Azure AI Content Understanding audio overview](https://learn.microsoft.com/azure/ai-services/content-understanding/audio/overview)
- [Conversation PII redaction overview](https://learn.microsoft.com/azure/ai-services/language-service/personally-identifiable-information/conversation-pii-overview)
- [Retrieval-augmented generation in Azure AI Search](https://learn.microsoft.com/azure/search/retrieval-augmented-generation-overview)
- [Azure Cosmos DB TTL](https://learn.microsoft.com/azure/cosmos-db/nosql/time-to-live)

## Open Questions

- Which call languages, regions, maximum durations, codecs, and recording formats must Content Understanding support?
- Is the live transcript, after-call transcript, or a reconciled version authoritative?
- Which raw artifacts have a legally approved purpose and retention period?
- Which taxonomy, policy library, sentiment scale, entity types, and relationship types are authoritative?
- What confidence and evidence thresholds require human review?
- Which users can retrieve conversation text, and how are document-level permissions synchronized with source systems?
- Is Foundry IQ available with the required features and residency, or will TalkSense initially expose Azure AI Search directly?
- How will reprocessing replace or coexist with prior analytics facts and embeddings?
- What are the recovery, throughput, cost, and completion-latency objectives for peak after-call volume?
