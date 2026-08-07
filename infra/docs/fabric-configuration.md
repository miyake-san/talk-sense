# Configuração Microsoft Fabric — Eventstream e Eventhouse (Plan B)

Este guia detalha como configurar **Fabric Eventstream** e **Eventhouse** para receber telemetria do Azure Event Hubs e disponibilizá-la para Power BI.

## Arquitetura

```
┌─────────────────┐         ┌───────────────────┐         ┌─────────────────┐
│  Azure Event    │         │ Fabric Eventstream│         │  Eventhouse     │
│     Hubs        │ ──────→ │  (Streaming ETL)  │ ──────→ │  (KQL Database) │
│ evh-voiceagent  │         │  - Transformação  │         │  - Armazenamento│
│   -telemetry    │         │  - Roteamento     │         │  - Consulta KQL │
└─────────────────┘         └───────────────────┘         └────────┬────────┘
                                                                     │
                                                            ┌────────▼────────┐
                                                            │   Power BI      │
                                                            │ Direct Lake / DQ│
                                                            └─────────────────┘
```

---

## Pré-requisitos

1. ✅ **Azure Event Hubs** já implantado (via Bicep/Terraform)
2. ✅ **Workspace identity do Fabric** com role **Azure Event Hubs Data Receiver** no Event Hub (auth keyless — SAS desabilitado)
3. ✅ **Microsoft Fabric capacity** ativa (F SKU)
4. ✅ **Workspace do Fabric** criado
5. ✅ **Permissões**:
   - Admin ou Contributor no workspace Fabric
   - Viewer/Contributor no Event Hub (para testar conexão)

---

## Parte 1: Criar Eventstream

### 1.1 Acessar o Workspace

1. Navegue para [https://app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Selecione ou crie um **Workspace** (ex: `VoiceAgentAnalytics`)
3. Certifique-se de que o workspace está em uma **Fabric capacity**

### 1.2 Criar Novo Eventstream

1. No workspace, clique em **+ Novo** → **Eventstream**
2. Nome: `VoiceAgentTelemetryStream`
3. Descrição: `Ingestão de telemetria do agente de voz via Event Hubs`
4. Clique em **Criar**

### 1.3 Adicionar Source (Azure Event Hubs)

1. No canvas do Eventstream, clique em **Add source** (ou arraste o tile)
2. Selecione **Azure Event Hubs**

#### 1.3.1 Configurar Conexão

> **Autenticação keyless (obrigatório):** o Event Hub tem SAS/local auth **desabilitado** — connection strings não funcionam. Use **Managed Identity / Entra ID**.

**Managed Identity (Entra ID)**

1. Em **Workspace settings → Workspace identity**, habilite a workspace identity e copie seu Object ID.
2. Passe esse Object ID como `listener_principal_id` (Terraform) ou `listenerPrincipalId` (Bicep); o IaC atribui **Azure Event Hubs Data Receiver** no Event Hub.
3. No Eventstream, em **Authentication**, selecione **Workspace identity** (não use Connection String / Shared Access Key).
4. Namespace (FQDN): `evhns-voiceagent-<env>-xxxxxx.servicebus.windows.net` (output `eventhub_namespace_fqdn` / `eventHubNamespaceFqdn`)
5. Event Hub name: `evh-voiceagent-telemetry`
6. Consumer group: `fabric-eventstream`
7. Data Format: `JSON` · Compression: `None`
8. Nome da Source: `EventHubsVoiceAgentSource`

### 1.4 Adicionar Transformações (Opcional)

Se precisar transformar eventos antes de gravar no Eventhouse:

1. Adicione **Transform** ao Eventstream
2. Use **Event Processor** para:
   - Filtrar eventos por `eventType`
   - Enriquecer com campos adicionais
   - Flatten JSON aninhado

**Exemplo de transformação KQL inline:**

```kql
// Filtrar apenas eventos de turno
| where eventType == "turn_completed"

// Adicionar campos calculados
| extend durationMinutes = todouble(payload.latencyMs) / 60000

// Renomear campos
| project-rename 
    ConversationId = conversationId,
    TurnIndex = payload.turnIndex,
    Intent = payload.intent
```

### 1.5 Adicionar Destination (Eventhouse)

1. No canvas, clique em **Add destination**
2. Selecione **Eventhouse**
3. Configure:

```
Passo 1: Selecionar Eventhouse
- Criar novo ou selecionar existente
- Nome: VoiceAgentEventhouse
- KQL Database: VoiceAgentDB

Passo 2: Tabela Destino
- Modo: Ingestão Direta (Direct Ingestion)
- Nome da tabela: RawTelemetry
- Formato: JSON
- Mapping: criar automaticamente (ou manual, ver seção abaixo)

Passo 3: Advanced Settings
- Ingestion batching: 
  - Max delay: 30 segundos (ajustar conforme necessidade de latência)
  - Max batch size: 1000 eventos
```

### 1.6 Ativar o Eventstream

1. Clique em **Publish** no canto superior direito
2. Aguarde provisionamento (1-2 minutos)
3. Status deve mudar para **Running**

---

## Parte 2: Configurar Eventhouse (KQL Database)

### 2.1 Criar Eventhouse (se ainda não existe)

1. No workspace, clique em **+ Novo** → **Eventhouse**
2. Nome: `VoiceAgentEventhouse`
3. Clique em **Criar**

### 2.2 Criar KQL Database

1. Dentro do Eventhouse, clique em **+ New KQL Database**
2. Nome: `VoiceAgentDB`
3. Retention: **365 days** (ajustar conforme necessidade)
4. Cache: **31 days** (hot cache para consultas rápidas)

### 2.3 Criar Tabelas

#### Opção A: Tabela RAW Única (Simples)

```kql
// Criar tabela RAW que recebe todos os eventos
.create table RawTelemetry (
    eventType: string,
    timestamp: datetime,
    conversationId: string,
    payload: dynamic
)

// Habilitar streaming ingestion
.alter table RawTelemetry policy streamingingestion enable

// Definir retention policy
.alter table RawTelemetry policy retention softdelete = 365d
```

#### Opção B: Tabelas Separadas por Tipo (Recomendado)

```kql
// 1. Conversas
.create table Conversations (
    conversationId: string,
    timestamp: datetime,
    sessionId: string,
    channel: string,
    customerIdAnon: string,
    customerSegment: string,
    initialIntent: string,
    originQueue: string,
    metadata: dynamic
)

// 2. Turnos
.create table Turns (
    conversationId: string,
    timestamp: datetime,
    turnIndex: int,
    userUtterance: string,
    agentResponse: string,
    intent: string,
    intentConfidence: real,
    entities: dynamic,
    sentimentOverall: string,
    sentimentScore: real,
    latencyMs: int,
    ttsEnabled: bool,
    bargeInDetected: bool
)

// 3. Eventos
.create table Events (
    conversationId: string,
    timestamp: datetime,
    eventName: string,
    eventCategory: string,
    turnIndex: int,
    details: dynamic
)

// 4. CSAT
.create table CSAT (
    conversationId: string,
    timestamp: datetime,
    score: int,
    scale: string,
    comment: string,
    collectedVia: string
)

// Habilitar streaming ingestion em todas
.alter table Conversations policy streamingingestion enable
.alter table Turns policy streamingingestion enable
.alter table Events policy streamingingestion enable
.alter table CSAT policy streamingingestion enable
```

### 2.4 Criar Update Policy (Roteamento Automático)

Se você usar a **tabela RAW única**, crie update policies para rotear eventos para tabelas específicas:

```kql
// Update policy: Conversations
.alter table Conversations policy update
@'[{
    "IsEnabled": true,
    "Source": "RawTelemetry",
    "Query": "RawTelemetry | where eventType == 'conversation_started' | project conversationId, timestamp, sessionId = tostring(payload.sessionId), channel = tostring(payload.channel), customerIdAnon = tostring(payload.customerIdAnon), customerSegment = tostring(payload.customerSegment), initialIntent = tostring(payload.initialIntent), originQueue = tostring(payload.originQueue), metadata = payload.metadata",
    "IsTransactional": false,
    "PropagateIngestionProperties": false
}]'

// Update policy: Turns
.alter table Turns policy update
@'[{
    "IsEnabled": true,
    "Source": "RawTelemetry",
    "Query": "RawTelemetry | where eventType == 'turn_completed' | project conversationId, timestamp, turnIndex = toint(payload.turnIndex), userUtterance = tostring(payload.userUtterance), agentResponse = tostring(payload.agentResponse), intent = tostring(payload.intent), intentConfidence = toreal(payload.intentConfidence), entities = payload.entities, sentimentOverall = tostring(payload.sentiment.overall), sentimentScore = toreal(payload.sentiment.score), latencyMs = toint(payload.latencyMs), ttsEnabled = tobool(payload.ttsEnabled), bargeInDetected = tobool(payload.bargeInDetected)",
    "IsTransactional": false,
    "PropagateIngestionProperties": false
}]'

// Update policy: Events
.alter table Events policy update
@'[{
    "IsEnabled": true,
    "Source": "RawTelemetry",
    "Query": "RawTelemetry | where eventType == 'conversation_event' | project conversationId, timestamp, eventName = tostring(payload.eventName), eventCategory = tostring(payload.eventCategory), turnIndex = toint(payload.turnIndex), details = payload.details",
    "IsTransactional": false,
    "PropagateIngestionProperties": false
}]'

// Update policy: CSAT
.alter table CSAT policy update
@'[{
    "IsEnabled": true,
    "Source": "RawTelemetry",
    "Query": "RawTelemetry | where eventType == 'csat_received' | project conversationId, timestamp, score = toint(payload.score), scale = tostring(payload.scale), comment = tostring(payload.comment), collectedVia = tostring(payload.collectedVia)",
    "IsTransactional": false,
    "PropagateIngestionProperties": false
}]'
```

### 2.5 Criar Views Analíticas

```kql
// View: Conversações com Desfecho
.create-or-alter function ConversationsWithOutcome() {
    Conversations
    | join kind=leftouter (
        Events
        | where eventName == "conversation_ended"
        | project conversationId, outcome = tostring(details.outcome), durationSeconds = toint(details.durationSeconds), totalTurns = toint(details.totalTurns)
    ) on conversationId
    | project-away conversationId1
}

// View: Métricas de Latência por Conversa
.create-or-alter function LatencyMetricsByConversation() {
    Turns
    | summarize 
        TMR = avg(latencyMs),
        TMA = max(latencyMs),
        TotalTurns = count()
      by conversationId
}

// View: Taxa de Retenção pela IA
.create-or-alter function AIRetentionRate() {
    Events
    | where eventName == "conversation_ended"
    | extend resolvedByAI = details.outcome == "resolved_by_ai"
    | summarize 
        TotalConversations = count(),
        ResolvedByAI = countif(resolvedByAI)
    | extend RetentionRate = toreal(ResolvedByAI) / TotalConversations * 100
}
```

### 2.6 Habilitar OneLake Availability (Direct Lake)

Para Power BI com **Direct Lake** (mais rápido):

1. No Eventhouse, vá em **Settings** → **OneLake availability**
2. **Enable** OneLake availability
3. Configure:
   - **Tabelas**: selecione todas (Conversations, Turns, Events, CSAT)
   - **Sync frequency**: 
     - Para POC: 5 minutos
     - Para produção: ajustar conforme necessidade de latência
   - **File format**: Delta Parquet (padrão)

> ⚠️ **Atenção**: Com OneLake availability ativado, **não é possível** fazer DELETE/TRUNCATE manual nas tabelas KQL. Use TTL policies para expiração automática.

---

## Parte 3: Testar o Fluxo End-to-End

### 3.1 Enviar Evento de Teste ao Event Hub

```bash
# Usando Azure CLI (substituir valores)
az eventhubs eventhub send \
  --resource-group rg-voiceagent-analytics-dev \
  --namespace-name evhns-voiceagent-dev-abc123 \
  --name evh-voiceagent-telemetry \
  --body '{
    "eventType": "conversation_started",
    "timestamp": "2026-07-02T15:00:00.000Z",
    "conversationId": "conv-test-001",
    "payload": {
      "sessionId": "sess-test",
      "channel": "phone",
      "customerIdAnon": "test-hash-123",
      "initialIntent": "test"
    }
  }'
```

### 3.2 Monitorar no Eventstream

1. Abra o Eventstream: `VoiceAgentTelemetryStream`
2. Visualize **Metrics**:
   - Input events (de Event Hubs)
   - Output events (para Eventhouse)
3. Verifique **Logs** se houver erros

### 3.3 Validar no Eventhouse

```kql
// Verificar se dados chegaram na tabela RAW
RawTelemetry
| where timestamp > ago(10m)
| order by timestamp desc
| take 10

// Verificar tabelas específicas
Conversations
| where timestamp > ago(10m)
| count

Turns
| where timestamp > ago(10m)
| count

Events
| where timestamp > ago(10m)
| count
```

---

## Parte 4: Otimizações e Best Practices

### 4.1 Particionamento

```kql
// Criar política de particionamento por data (recomendado para grandes volumes)
.alter table RawTelemetry policy partitioning
@'{
  "PartitionKeys": [
    {
      "ColumnName": "timestamp",
      "Kind": "UniformRange",
      "Properties": {
        "Reference": "1970-01-01T00:00:00",
        "RangeSize": "1.00:00:00",
        "OverrideCreationTime": false
      }
    }
  ]
}'
```

### 4.2 Caching

```kql
// Cache de 7 dias para consultas rápidas
.alter table Turns policy caching hot = 7d

// Cache maior para tabela de conversas (menor volume)
.alter table Conversations policy caching hot = 30d
```

### 4.3 Retention (TTL)

```kql
// Reter dados por 1 ano, soft delete
.alter table RawTelemetry policy retention 
@'{
  "SoftDeletePeriod": "365.00:00:00",
  "Recoverability": "Disabled"
}'
```

### 4.4 Ingestion Batching

```kql
// Otimizar batching para latência ou throughput
.alter table RawTelemetry policy ingestionbatching
@'{
  "MaximumBatchingTimeSpan": "00:00:30",
  "MaximumNumberOfItems": 1000,
  "MaximumRawDataSizeMB": 100
}'

// Para latência mínima (near real-time):
.alter table Turns policy ingestionbatching
@'{
  "MaximumBatchingTimeSpan": "00:00:05",
  "MaximumNumberOfItems": 100,
  "MaximumRawDataSizeMB": 10
}'
```

---

## Parte 5: Troubleshooting

### Problema: Eventos não chegam no Eventhouse

**Checklist:**

1. ✅ Eventstream está **Running**?
2. ✅ Consumer group correto (`fabric-eventstream`)?
3. ✅ Workspace identity habilitada e com role Data Receiver?
4. ✅ Event Hub tem dados? (verificar no Azure Portal: Metrics → Incoming Messages)
5. ✅ Tabela de destino existe no Eventhouse?
6. ✅ Streaming ingestion habilitada na tabela?

**Logs:**

```kql
// Ver últimas falhas de ingestão
.show ingestion failures
| where Table == "RawTelemetry"
| where Timestamp > ago(1h)
| order by Timestamp desc
```

### Problema: Update Policy não funciona

```kql
// Verificar se policy está habilitada
.show table Conversations policy update

// Testar query da policy manualmente
RawTelemetry
| where eventType == 'conversation_started'
| project 
    conversationId, 
    timestamp, 
    sessionId = tostring(payload.sessionId),
    channel = tostring(payload.channel)
| take 10
```

### Problema: Latência alta

1. **Reduzir batching delay** (ver seção 4.4)
2. **Aumentar throughput units** do Event Hub
3. **Verificar partições**: ideal 1 partição para cada 1 MB/s de throughput
4. **Ativar Eventhouse cache** para consultas frequentes

---

## Próximos Passos

1. ✅ **Eventstream e Eventhouse configurados**
2. ⏭️ **Conectar Power BI** ao Eventhouse (ver `powerbi-configuration.md`)
3. ⏭️ **Implementar sender no agent** (ver `event-hub-message-format.md`)
4. ⏭️ **Criar dashboards** com as 9 métricas (ver `../../docs/powerbi-prompts.md`)
5. ⏭️ **Testar com carga real**

## Referências

- [Fabric Eventstream Documentation](https://learn.microsoft.com/fabric/real-time-intelligence/event-streams/)
- [Eventhouse & KQL Database](https://learn.microsoft.com/fabric/real-time-intelligence/eventhouse)
- [KQL Quick Reference](https://learn.microsoft.com/azure/data-explorer/kusto/query/)
- [OneLake Availability](https://learn.microsoft.com/fabric/real-time-intelligence/onelake-availability)
- [Update Policies](https://learn.microsoft.com/azure/data-explorer/kusto/management/update-policy)
