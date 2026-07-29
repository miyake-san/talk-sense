# ADR-002 — Add Voice Module with Microsoft Foundry Realtime Audio

- **Status:** Proposed
- **Date:** 2026-07-29

## Context

TalkSense has no frontend, backend, media gateway, telephony integration, or audio code. The existing repository begins after a voice system has produced analytics events. Its documented producer sends JSON to Azure Event Hubs, and its current infrastructure and Fabric assets should remain the analytics destination rather than become the media path.

The target experience requires low-latency, bidirectional speech, transcript capture, interruption handling, safe text fallback, and transfer to a human. Microsoft Foundry audio models and Azure OpenAI GPT Realtime support three relevant transports:

- WebRTC for direct, low-latency browser or mobile media;
- WebSocket for trusted server-to-server media and control;
- SIP for PBX, SBC, PSTN, and contact-center telephony.

The realtime API is stateful and event-driven. Audio transport, model session state, business tools, transcript persistence, and analytics events need separate ownership. Browser clients must not receive a long-lived Azure credential.

## Decision

Introduce a transport-neutral voice module around the Conversation Orchestrator from ADR-001:

- **WebRTC is the selected transport for the browser prototype.**
- **SIP is the selected target for contact-center integration.**
- **WebSocket is the selected server-to-server adapter and observer/control transport, not the default browser transport.**

The production telephony adapter may connect a validated SIP trunk/SBC directly to the Realtime SIP endpoint or use Azure Communication Services/Voice Live as an integration layer when PSTN acquisition, recording, transfer, conferencing, or an existing contact-center platform requires it. That choice must be proven with the target carrier and contact-center product before production.

### Browser session flow

1. The browser authenticates to a future TalkSense session API or requests a constrained anonymous session.
2. The API evaluates locale, consent policy, customer permissions, quota, and allowed tools.
3. The API creates a narrowly scoped realtime session and returns a short-lived ephemeral credential or proxies the SDP exchange. Long-lived model keys never reach the browser.
4. The browser establishes the WebRTC peer connection and uses the data channel for realtime control events.
5. The realtime model streams audio responses. Business tool calls are executed through the authenticated application/tool gateway, never directly from the browser.
6. The backend optionally opens a controller/observer WebSocket for server-side policy, tool, transcript, and handoff coordination.
7. Confirmed transcript deltas are assembled into ordered turns. Only completed, normalized turns are offered to the persistence and mining pipeline.
8. A redacted event projection is sent to Event Hubs using ADR-004. Raw audio is never sent to Event Hubs.
9. On session close, the backend finalizes duration and outcome, stores the permitted artifacts, and enqueues asynchronous mining.

### SIP session flow

1. The telephony provider, PBX, or SBC routes the call to the approved SIP endpoint.
2. The application validates the signed incoming-call notification and evaluates routing, consent, locale, and fraud controls.
3. The application accepts or rejects the call and applies the server-owned realtime session configuration.
4. Realtime audio and control events use the SIP media session; tools continue through the application gateway.
5. On escalation, the application transfers/refers the call to an approved queue or uses the contact-center/ACS transfer API.
6. The handoff package is delivered out of band to the human desktop or case system and contains a redacted summary, intent, completed verification steps, relevant citations, sentiment trend, and transfer reason.

### Interruption and barge-in

Use server voice activity detection initially, with parameters tuned per locale and acoustic environment. When user speech begins while assistant audio is playing:

1. stop local playback and record the exact played-audio offset;
2. send response cancellation;
3. truncate the unplayed part of the assistant conversation item at the played offset;
4. clear queued output audio;
5. preserve the user's new speech as the next turn and resume orchestration.

Cancellation and truncation are both required: cancellation stops generation, while truncation keeps server conversation state consistent with what the caller actually heard. Clients must deduplicate event IDs and tolerate cancellation races.

### Degradation and human handoff

The voice module uses the following ordered fallback:

1. retry a transient media/model operation within a bounded latency budget;
2. switch to server-mediated WebSocket only when the channel supports it and the failure is transport-specific;
3. offer text chat when a visual channel is available;
4. provide a deterministic status message and transfer to a human;
5. if transfer fails, capture a callback request with explicit confirmation and minimal data.

Handoff is also triggered by customer request, repeated no-match/no-input, authentication failure, policy mandate, safety concern, low answer confidence, unavailable required tool, or exhausted latency/error budget.

## Options Considered

| Option | Strengths | Limitations | Decision |
| --- | --- | --- | --- |
| WebRTC | Lowest browser latency, built-in media handling, NAT traversal, data channel | Browser session security and SDP/ephemeral-token broker required; not a PBX protocol | Selected for browser prototype |
| WebSocket | Simple trusted server integration and full media/control mediation | Application owns audio chunking, backpressure, buffering, and often more latency; unsuitable for untrusted browser credentials | Selected for server adapters and control |
| SIP | Native PBX/SBC/contact-center interop, inbound calls, transfer/refer | Carrier certification, SBC, codec, DTMF, emergency-calling, recording, and regional constraints | Selected for contact-center target |
| Batch speech-to-text plus text agent plus text-to-speech | Simple component boundaries and independently replaceable models | Higher turn latency and weaker natural interruption behavior | Fallback for unsupported regions or stricter deterministic processing |
| Fabric/Event Hubs in the media loop | Reuses current infrastructure | Event Hubs is not a realtime bidirectional media transport and Fabric is an analytics plane | Rejected |

## Consequences

### Positive

- WebRTC provides the shortest path for validating natural browser conversation and barge-in.
- SIP creates a clear path to real contact-center and PSTN integration.
- A transport abstraction keeps orchestration, tools, transcript processing, and analytics independent of the channel.
- Existing Event Hubs, Eventstream, Eventhouse, and Power BI assets remain reusable.

### Negative

- TalkSense must add an entirely new application and media plane.
- Supporting WebRTC, WebSocket, and SIP introduces different authentication, failure, codec, networking, and test requirements.
- Realtime model sessions are stateful; reconnect and failover can lose ephemeral context unless the application maintains a compact recoverable state.
- Transcript timing, model output, and actual played audio can diverge during interruption and must be reconciled.
- SIP and recording behavior depends on carrier, jurisdiction, contact-center platform, and regional service availability.

## Security and Governance Considerations

- Issue only short-lived, session-bound browser credentials. Bind server-created sessions to user, tenant, origin, channel, tool policy, model, expiry, and rate limit.
- Protect session creation against replay, origin abuse, denial of service, and unexpected cost. Use Entra ID for employees and an approved customer identity or constrained anonymous-token design for callers.
- Validate signed SIP webhooks, restrict source networks where supported, enforce anti-fraud controls, and allow-list transfer destinations.
- Keep authoritative authorization and side effects in the backend. The realtime model can request a tool but cannot grant itself permission.
- Announce recording and AI use, capture consent before persistence, and support decline/withdrawal paths as defined in ADR-007.
- Do not persist pre-consent audio. Do not place raw audio, unredacted transcripts, model credentials, payment data, or authentication factors in Event Hubs events.
- Encrypt recordings and transcripts, isolate them from analytics stores, and apply separate access and retention policies.
- DTMF and spoken payment credentials must be handled by a PCI-compliant mechanism outside model context and standard telemetry.

## Observability and Evaluation

Correlate client, media, realtime API, orchestrator, tool, handoff, and analytics spans without recording sensitive payloads by default.

Monitor:

- session setup success, ICE connection time, reconnects, and abnormal closure;
- time to first input transcription, time to first audio, turn latency, and tool latency;
- round-trip time, jitter, packet loss, bitrate, codec, audio gaps, no-input, and no-match;
- speech-start detection, false endpointing, barge-in count, cancel-to-silence time, and truncation consistency;
- transcription word/error quality by locale and acoustic cohort;
- containment, transfer success, caller abandonment, fallback-to-text, callback requests, and post-handoff repeats;
- model, transport, quota, tool, and application error rates.

Evaluation must use scripted calls and human listening tests across supported languages, accents, devices, noise, echo, packet impairment, rapid interruptions, long silence, and accessibility scenarios. Release gates include latency percentiles, transcription quality, task success, interruption correctness, safety, PII leakage, and successful human transfer.

## Implementation Notes

- Because there is no existing frontend/backend, first create a minimal text/session API boundary; do not embed realtime credentials or business tools in a static client.
- Keep the current Event Hubs schema available during migration, then emit the versioned envelope in ADR-004 from the session backend.
- Start with a browser-only WebRTC thin slice: consent, one read-only knowledge tool, transcript finalization, interruption, and text fallback.
- Add a server controller only for controls that cannot safely live in the client. Avoid routing all browser audio through the application without a measured security or integration need.
- Confirm the current generally available API path and supported realtime model in the linked WebRTC, WebSocket, and SIP documentation at implementation time. Do not copy retired preview endpoint formats from samples.
- Run a SIP proof of concept with the chosen PBX/contact-center vendor covering codecs, DTMF, inbound validation, transfer, recording, queue context, failover, and regional routing.
- Keep voice recordings in a restricted Blob/ADLS account and send only a storage reference to the after-call pipeline.

Primary references:

- [Use the GPT Realtime API via WebRTC](https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-webrtc)
- [Use the GPT Realtime API via WebSocket](https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-websockets)
- [Use the GPT Realtime API via SIP](https://learn.microsoft.com/azure/foundry/openai/how-to/realtime-audio-sip)
- [Azure Communication Services contact-center guidance](https://learn.microsoft.com/azure/communication-services/tutorials/contact-center)
- [Azure Communication Services call recording](https://learn.microsoft.com/azure/communication-services/concepts/voice-video-calling/call-recording)

## Open Questions

- Which browser, mobile, PBX, SBC, carrier, and contact-center products are in scope?
- Should production SIP terminate directly at the realtime service or through Azure Communication Services/Voice Live?
- Which codecs, DTMF modes, languages, regions, phone-number countries, and emergency-call constraints are required?
- What are the p50, p95, and p99 latency, availability, and recovery objectives?
- Can a call continue with transient processing when recording consent is declined, or must it transfer immediately?
- Which transcript events are authoritative when model transcripts, client playback, and contact-center recordings differ?
- What context and verification state may be shown to a human agent?
- Who owns telecom fraud monitoring, carrier certification, recording notices, and jurisdiction-specific consent rules?
