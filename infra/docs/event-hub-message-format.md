# Event Hub Message Format — Voice Agent Telemetry (Plan B)

Este documento define o **formato JSON das mensagens de telemetria** que o agente de voz deve enviar para o **Azure Event Hubs** no Plano B.

## Arquitetura

```
┌──────────────┐         ┌───────────────┐         ┌─────────────┐         ┌──────────┐
│ Voice Agent  │ ──JSON─→ │  Event Hubs   │ ──────→ │  Eventstream│ ──────→ │Eventhouse│
│  (Vendor)    │  (HTTPS/ │ (evh-voiceagent│         │  (Fabric)   │         │(KQL DB)  │
│              │   AMQP)  │   -telemetry)  │         │             │         │          │
└──────────────┘         └───────────────┘         └─────────────┘         └────┬─────┘
                                                                                  │
                                                                            ┌─────▼─────┐
                                                                            │ Power BI  │
                                                                            │Direct Lake│
                                                                            └───────────┘
```

## Tipos de Evento

O sistema captura **4 tipos de eventos principais**:

1. **Conversa Iniciada** (`conversation_started`)
2. **Turno Concluído** (`turn_completed`)
3. **Evento de Conversa** (`conversation_event`)
4. **CSAT Recebido** (`csat_received`)

Cada mensagem enviada ao Event Hub deve incluir:
- **`eventType`**: tipo do evento
- **`timestamp`**: ISO 8601 UTC
- **`conversationId`**: identificador único da conversa
- **`payload`**: dados específicos do evento

---

## 1. Evento: Conversa Iniciada

### Quando Enviar
No início de cada atendimento, antes do primeiro turno.

### Estrutura JSON

```json
{
  "eventType": "conversation_started",
  "timestamp": "2026-07-02T14:30:15.123Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "sessionId": "sess-xyz789",
    "channel": "phone",
    "customerIdAnon": "hash_cliente_12345678",
    "customerSegment": "Premium",
    "initialIntent": "saldo",
    "originQueue": "investimentos_principal",
    "metadata": {
      "region": "BR-SP",
      "languageCode": "pt-BR"
    }
  }
}
```

### Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `eventType` | string | ✅ | Sempre `"conversation_started"` |
| `timestamp` | string (ISO 8601) | ✅ | Timestamp UTC do início |
| `conversationId` | string | ✅ | ID único da conversa (formato: `conv-{data}-{uniqueid}`) |
| `payload.sessionId` | string | ✅ | ID da sessão (vendor) |
| `payload.channel` | string | ✅ | Canal: `phone`, `chat`, `whatsapp` |
| `payload.customerIdAnon` | string | ⚠️ | Hash SHA256 do ID real do cliente (LGPD) |
| `payload.customerSegment` | string | ❌ | Segmentação: `Premium`, `Standard`, etc. |
| `payload.initialIntent` | string | ❌ | Intenção detectada no início |
| `payload.originQueue` | string | ❌ | Fila de origem (URA) |
| `payload.metadata` | object | ❌ | Metadados adicionais |

---

## 2. Evento: Turno Concluído

### Quando Enviar
Após cada turno (interação usuário ↔ agente).

### Estrutura JSON

```json
{
  "eventType": "turn_completed",
  "timestamp": "2026-07-02T14:30:18.456Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "turnIndex": 1,
    "userUtterance": "Quero saber meu saldo",
    "agentResponse": "Consultando seu saldo. Seu saldo atual é R$ 12.345,67.",
    "intent": "saldo",
    "intentConfidence": 0.95,
    "entities": [
      {"type": "account_type", "value": "corrente"}
    ],
    "sentiment": {
      "overall": "neutral",
      "score": 0.52
    },
    "latencyMs": 1250,
    "ttsEnabled": true,
    "bargeInDetected": false
  }
}
```

### Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `eventType` | string | ✅ | Sempre `"turn_completed"` |
| `timestamp` | string (ISO 8601) | ✅ | Timestamp UTC do fim do turno |
| `conversationId` | string | ✅ | ID da conversa (vinculação) |
| `payload.turnIndex` | number | ✅ | Índice sequencial do turno (1, 2, 3...) |
| `payload.userUtterance` | string | ⚠️ | Fala do cliente (pode conter PII) |
| `payload.agentResponse` | string | ✅ | Resposta do agente IA |
| `payload.intent` | string | ✅ | Intenção detectada |
| `payload.intentConfidence` | number | ❌ | Confiança (0.0-1.0) |
| `payload.entities` | array | ❌ | Entidades extraídas |
| `payload.sentiment.overall` | string | ❌ | `positive`, `neutral`, `negative` |
| `payload.sentiment.score` | number | ❌ | Score -1.0 a +1.0 |
| `payload.latencyMs` | number | ✅ | Latência total do turno (ms) |
| `payload.ttsEnabled` | boolean | ❌ | TTS ativo neste turno? |
| `payload.bargeInDetected` | boolean | ❌ | Cliente interrompeu? |

> ⚠️ **LGPD**: Se `userUtterance` contiver dados sensíveis (CPF, nome completo), considere:
> - Mascaramento antes do envio, ou
> - Não enviar este campo, ou
> - Aplicar hash/tokenização

---

## 3. Evento: Evento de Conversa

### Quando Enviar
Quando ocorre um evento significativo durante a conversa (transferência, erro, fallback, menu URA, etc.).

### Estrutura JSON

```json
{
  "eventType": "conversation_event",
  "timestamp": "2026-07-02T14:30:25.789Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "eventName": "agent_requested",
    "eventCategory": "handoff",
    "turnIndex": 3,
    "details": {
      "reason": "complex_query",
      "targetQueue": "atendimento_humano_premium"
    }
  }
}
```

### Tipos de `eventName`

| `eventName` | `eventCategory` | Descrição |
|-------------|-----------------|-----------|
| `agent_requested` | `handoff` | Cliente pediu atendente humano |
| `transferred_to_agent` | `handoff` | Transferência efetivada |
| `no_comprehension` | `error` | Não compreendeu a fala |
| `knowledge_gap` | `error` | Não tem conhecimento para responder |
| `system_error` | `error` | Erro técnico (timeout, API failure) |
| `returned_to_ura` | `navigation` | Cliente voltou ao menu URA |
| `barge_in` | `interaction` | Cliente interrompeu agente |
| `silence_timeout` | `interaction` | Cliente ficou em silêncio |
| `conversation_ended` | `completion` | Fim da conversa (ver campo `outcome`) |

### Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `eventType` | string | ✅ | Sempre `"conversation_event"` |
| `timestamp` | string (ISO 8601) | ✅ | Timestamp UTC do evento |
| `conversationId` | string | ✅ | ID da conversa |
| `payload.eventName` | string | ✅ | Nome do evento (ver tabela) |
| `payload.eventCategory` | string | ✅ | Categoria: `handoff`, `error`, `navigation`, `interaction`, `completion` |
| `payload.turnIndex` | number | ❌ | Turno onde ocorreu (se aplicável) |
| `payload.details` | object | ❌ | Detalhes adicionais específicos do evento |

### Exemplo: Conversa Encerrada

```json
{
  "eventType": "conversation_event",
  "timestamp": "2026-07-02T14:35:00.123Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "eventName": "conversation_ended",
    "eventCategory": "completion",
    "turnIndex": 8,
    "details": {
      "outcome": "resolved_by_ai",
      "durationSeconds": 285,
      "totalTurns": 8
    }
  }
}
```

### Valores de `outcome`

- `resolved_by_ai` — Resolvido pela IA
- `transferred_to_agent` — Transferido para humano
- `customer_hangup` — Cliente desligou
- `system_timeout` — Timeout do sistema

---

## 4. Evento: CSAT Recebido

### Quando Enviar
Quando o cliente fornece feedback (CSAT/NPS) após o atendimento.

### Estrutura JSON

```json
{
  "eventType": "csat_received",
  "timestamp": "2026-07-02T14:36:00.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "score": 5,
    "scale": "1-5",
    "comment": "Atendimento rápido e eficiente",
    "collectedVia": "post_call_ivr"
  }
}
```

### Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `eventType` | string | ✅ | Sempre `"csat_received"` |
| `timestamp` | string (ISO 8601) | ✅ | Timestamp UTC da coleta |
| `conversationId` | string | ✅ | ID da conversa |
| `payload.score` | number | ✅ | Nota dada pelo cliente |
| `payload.scale` | string | ✅ | Escala: `1-5`, `0-10`, etc. |
| `payload.comment` | string | ❌ | Comentário opcional |
| `payload.collectedVia` | string | ❌ | Método: `post_call_ivr`, `email`, `sms` |

---

## Convenções Gerais

### 1. Formato de Timestamp

- **Formato**: ISO 8601 UTC
- **Exemplo**: `"2026-07-02T14:30:15.123Z"`
- **Timezone**: Sempre UTC (`Z`)

### 2. Partition Key

Para distribuição eficiente no Event Hub, use **`conversationId`** como partition key:

```javascript
// Node.js (@azure/event-hubs)
const eventData = {
  body: telemetryEvent,
  partitionKey: telemetryEvent.conversationId
};
```

Isso garante que todos os eventos da mesma conversa vão para a mesma partição (ordem preservada).

### 3. Content Type

- **MIME type**: `application/json`
- **Encoding**: UTF-8

### 4. Tamanho Máximo

- Event Hub Standard: **1 MB** por mensagem
- Recomendação: mantenha cada evento < **256 KB**

### 5. Tratamento de PII (LGPD)

**Antes de enviar ao Event Hub:**

1. **Anonimizar IDs de cliente**: use SHA256 hash
   ```javascript
   const crypto = require('crypto');
   const customerIdAnon = crypto.createHash('sha256').update(realCustomerId).digest('hex');
   ```

2. **Mascarar ou remover `userUtterance`** se contiver:
   - CPF, RG, passaporte
   - Nome completo
   - Endereço, telefone

3. **Alternativas**:
   - Enviar apenas `intent` e `entities` processados
   - Aplicar NER (Named Entity Recognition) para detectar e mascarar PII
   - Armazenar transcrição completa em local seguro separado

---

## Exemplo Completo: Fluxo de 1 Conversa

### 1. Início

```json
{
  "eventType": "conversation_started",
  "timestamp": "2026-07-02T14:30:15.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "sessionId": "sess-xyz789",
    "channel": "phone",
    "customerIdAnon": "a3d5e7f9b1c2d4e6f8a0b2c4d6e8f0a1",
    "initialIntent": "saldo"
  }
}
```

### 2. Turnos

```json
{
  "eventType": "turn_completed",
  "timestamp": "2026-07-02T14:30:18.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "turnIndex": 1,
    "userUtterance": "[MASKED]",
    "agentResponse": "Seu saldo é R$ 12.345,67.",
    "intent": "saldo",
    "latencyMs": 1250
  }
}
```

### 3. Evento: Cliente pede atendente

```json
{
  "eventType": "conversation_event",
  "timestamp": "2026-07-02T14:30:25.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "eventName": "agent_requested",
    "eventCategory": "handoff",
    "turnIndex": 3,
    "details": {"reason": "complex_query"}
  }
}
```

### 4. Encerramento

```json
{
  "eventType": "conversation_event",
  "timestamp": "2026-07-02T14:35:00.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "eventName": "conversation_ended",
    "eventCategory": "completion",
    "details": {
      "outcome": "transferred_to_agent",
      "durationSeconds": 285
    }
  }
}
```

### 5. CSAT

```json
{
  "eventType": "csat_received",
  "timestamp": "2026-07-02T14:36:00.000Z",
  "conversationId": "conv-20260702-143015-abc123",
  "payload": {
    "score": 4,
    "scale": "1-5"
  }
}
```

---

## Implementação no Agent

### Node.js (@azure/event-hubs)

```javascript
const { EventHubProducerClient } = require("@azure/event-hubs");
const { DefaultAzureCredential } = require("@azure/identity");

// Autenticação keyless via Managed Identity / Entra ID (sem connection string / SAS)
const fullyQualifiedNamespace = process.env.EVENTHUB_FQDN; // ex.: evhns-....servicebus.windows.net
const eventHubName = "evh-voiceagent-telemetry";

const producer = new EventHubProducerClient(fullyQualifiedNamespace, eventHubName, new DefaultAzureCredential());

async function sendTelemetry(telemetryEvent) {
  const batch = await producer.createBatch();
  
  const eventData = {
    body: telemetryEvent,
    contentType: "application/json",
    partitionKey: telemetryEvent.conversationId
  };
  
  batch.tryAdd(eventData);
  await producer.sendBatch(batch);
}

// Exemplo de uso
const event = {
  eventType: "conversation_started",
  timestamp: new Date().toISOString(),
  conversationId: "conv-" + Date.now(),
  payload: {
    sessionId: "sess-abc",
    channel: "phone",
    customerIdAnon: "hash123"
  }
};

await sendTelemetry(event);
```

### Python (azure-eventhub)

```python
from azure.eventhub import EventHubProducerClient, EventData
from azure.identity import DefaultAzureCredential
import json
import os
from datetime import datetime, timezone

# Autenticação keyless via Managed Identity / Entra ID (sem connection string / SAS)
fully_qualified_namespace = os.getenv("EVENTHUB_FQDN")  # ex.: evhns-....servicebus.windows.net
eventhub_name = "evh-voiceagent-telemetry"

producer = EventHubProducerClient(
    fully_qualified_namespace=fully_qualified_namespace,
    eventhub_name=eventhub_name,
    credential=DefaultAzureCredential(),
)

def send_telemetry(telemetry_event):
    event_data = EventData(json.dumps(telemetry_event))
    event_data.content_type = "application/json"
    event_data.partition_key = telemetry_event["conversationId"]
    
    with producer:
        producer.send_event(event_data)

# Exemplo
event = {
    "eventType": "turn_completed",
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "conversationId": "conv-123",
    "payload": {
        "turnIndex": 1,
        "agentResponse": "Olá!",
        "intent": "greeting",
        "latencyMs": 800
    }
}

send_telemetry(event)
```

---

## Validação

### Schema JSON

Um schema JSON Schema (opcional) pode ser criado para validação antes do envio:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["eventType", "timestamp", "conversationId", "payload"],
  "properties": {
    "eventType": {
      "type": "string",
      "enum": ["conversation_started", "turn_completed", "conversation_event", "csat_received"]
    },
    "timestamp": {
      "type": "string",
      "format": "date-time"
    },
    "conversationId": {
      "type": "string",
      "pattern": "^conv-"
    },
    "payload": {
      "type": "object"
    }
  }
}
```

---

## Próximos Passos

1. ✅ **Deploy da infraestrutura** (Event Hubs via Bicep/Terraform)
2. ⏭️ **Configurar Fabric Eventstream** (consumir do Event Hub)
3. ⏭️ **Criar Eventhouse/KQL Database** (definir tabelas)
4. ⏭️ **Implementar envio no agent** (SDK Event Hubs)
5. ⏭️ **Testar fluxo end-to-end** (agent → Event Hub → Eventstream → Eventhouse)
6. ⏭️ **Conectar Power BI** (DirectQuery/Direct Lake)

## Referências

- [Azure Event Hubs: Send/Receive Events](https://learn.microsoft.com/azure/event-hubs/event-hubs-dotnet-standard-getstarted-send)
- [Event Hubs Best Practices](https://learn.microsoft.com/azure/event-hubs/event-hubs-best-practices)
- [Fabric Eventstream Sources](https://learn.microsoft.com/fabric/real-time-intelligence/event-streams/add-source-azure-event-hubs)
- [Eventhouse KQL Database](https://learn.microsoft.com/fabric/real-time-intelligence/eventhouse)
- [LGPD: Anonimização de Dados](https://www.gov.br/governodigital/pt-br/seguranca-e-protecao-de-dados/protecao-de-dados)
