# Diagrama de Arquitetura Detalhado — Plan B

Este documento apresenta diagramas detalhados da arquitetura do Plano B para telemetria e analytics do agente de voz.

---

## Visão Geral da Arquitetura

```mermaid
graph LR
    A[Voice Agent<br/>Vendor] -->|HTTPS/AMQP<br/>JSON Events| B[Azure Event Hubs]
    B -->|Native Connector<br/>Consumer Group| C[Fabric Eventstream]
    C -->|Direct Ingestion<br/>Streaming ETL| D[Eventhouse<br/>KQL Database]
    D -->|Direct Lake<br/>or DirectQuery| E[Power BI<br/>Dashboards]
    
    D -->|OneLake<br/>Delta Parquet| F[OneLake]
    F -.->|Direct Lake<br/>Mode| E
    
    style A fill:#e1f5ff
    style B fill:#fff4e1
    style C fill:#ffe1f5
    style D fill:#f5e1ff
    style E fill:#e1ffe1
    style F fill:#f5ffe1
```

---

## Fluxo de Dados Detalhado

### 1. Ingestão (Voice Agent → Event Hubs)

```mermaid
sequenceDiagram
    participant Agent as Voice Agent
    participant SDK as Event Hub SDK
    participant EH as Event Hub<br/>(evh-voiceagent-telemetry)
    participant CG as Consumer Group<br/>(fabric-eventstream)
    
    Agent->>SDK: sendBatch(events)
    Note over Agent,SDK: JSON format<br/>4 event types
    SDK->>EH: Publish to partition<br/>(partitionKey=conversationId)
    EH->>EH: Store (7 days retention)
    EH->>CG: Available for consumption
    Note over CG: Eventstream pulls<br/>from this consumer group
```

**Tipos de Eventos Enviados**:
1. `conversation_started` — Início do atendimento
2. `turn_completed` — Fim de cada turno (user ↔ agent)
3. `conversation_event` — Eventos especiais (erro, transbordo, etc.)
4. `csat_received` — Feedback do cliente

---

### 2. Processamento (Eventstream → Eventhouse)

```mermaid
graph TD
    A[Event Hub<br/>Consumer Group] -->|Consume| B[Fabric Eventstream]
    B --> C{Event Processor}
    C -->|Route by eventType| D[Update Policy<br/>or Direct Ingestion]
    D --> E1[Conversations Table]
    D --> E2[Turns Table]
    D --> E3[Events Table]
    D --> E4[CSAT Table]
    
    E1 --> F[Eventhouse<br/>KQL Database]
    E2 --> F
    E3 --> F
    E4 --> F
    
    F -->|OneLake Availability| G[OneLake<br/>Delta Parquet]
    
    style A fill:#fff4e1
    style B fill:#ffe1f5
    style C fill:#f5e1ff
    style F fill:#f5e1ff
    style G fill:#f5ffe1
```

**Opções de Ingestão**:

**A) Tabela RAW Única + Update Policies**:
```kql
RawTelemetry (all events) 
  → Update Policy → Conversations
  → Update Policy → Turns
  → Update Policy → Events
  → Update Policy → CSAT
```

**B) Direct Ingestion (Recomendado)**:
```
Eventstream routes directly to target tables based on eventType
```

---

### 3. Modelagem (Eventhouse Schema)

```mermaid
erDiagram
    CONVERSATIONS ||--o{ TURNS : "has"
    CONVERSATIONS ||--o{ EVENTS : "has"
    CONVERSATIONS ||--o| CSAT : "receives"
    
    CONVERSATIONS {
        string conversationId PK
        datetime timestamp
        string sessionId
        string channel
        string customerIdAnon
        string customerSegment
        string initialIntent
        string originQueue
        dynamic metadata
    }
    
    TURNS {
        string conversationId FK
        datetime timestamp
        int turnIndex
        string userUtterance
        string agentResponse
        string intent
        real intentConfidence
        dynamic entities
        string sentimentOverall
        real sentimentScore
        int latencyMs
        bool ttsEnabled
        bool bargeInDetected
    }
    
    EVENTS {
        string conversationId FK
        datetime timestamp
        string eventName
        string eventCategory
        int turnIndex
        dynamic details
    }
    
    CSAT {
        string conversationId FK
        datetime timestamp
        int score
        string scale
        string comment
        string collectedVia
    }
```

---

### 4. Analytics (Eventhouse → Power BI)

```mermaid
graph TB
    A[Eventhouse KQL Database] --> B{OneLake Availability}
    B -->|Enabled| C[OneLake<br/>Delta Parquet]
    B -->|Disabled| D[DirectQuery<br/>KQL Endpoint]
    
    C --> E[Power BI<br/>Direct Lake Mode]
    D --> F[Power BI<br/>DirectQuery Mode]
    
    E --> G[Semantic Model]
    F --> G
    
    G --> H[Dashboard Page 1:<br/>Overview]
    G --> I[Dashboard Page 2:<br/>Conversation Detail]
    G --> J[Dashboard Page 3:<br/>Errors & Handoffs]
    
    H --> K[9 Core Metrics<br/>+ Visualizations]
    I --> L[Drill-through<br/>+ Transcript]
    J --> M[Error Analysis<br/>+ Overflow Metrics]
    
    style A fill:#f5e1ff
    style C fill:#f5ffe1
    style E fill:#e1ffe1
    style G fill:#e1ffe1
    style K fill:#e1f5ff
    style L fill:#e1f5ff
    style M fill:#e1f5ff
```

**Modos de Conexão**:

| Modo | Latência | Performance | Requer OneLake |
|------|----------|-------------|----------------|
| **Direct Lake** | ~5 min | ⚡⚡⚡ Excelente | ✅ Sim |
| **DirectQuery** | Segundos | ⚡⚡ Boa | ❌ Não |
| **Import** | Manual refresh | ⚡ Regular | ❌ Não (não recomendado) |

---

## Fluxo de Mensagem Completo (1 Conversa)

```mermaid
sequenceDiagram
    participant Agent
    participant EH as Event Hubs
    participant ES as Eventstream
    participant KQL as Eventhouse
    participant PBI as Power BI
    
    Note over Agent: Conversa inicia
    Agent->>EH: conversation_started
    EH->>ES: Pull event
    ES->>KQL: Insert into Conversations
    
    Note over Agent: Turno 1
    Agent->>EH: turn_completed (turn 1)
    EH->>ES: Pull event
    ES->>KQL: Insert into Turns
    
    Note over Agent: Turno 2
    Agent->>EH: turn_completed (turn 2)
    EH->>ES: Pull event
    ES->>KQL: Insert into Turns
    
    Note over Agent: Cliente pede atendente
    Agent->>EH: conversation_event<br/>(agent_requested)
    EH->>ES: Pull event
    ES->>KQL: Insert into Events
    
    Note over Agent: Conversa encerra
    Agent->>EH: conversation_event<br/>(conversation_ended)
    EH->>ES: Pull event
    ES->>KQL: Insert into Events
    
    Note over Agent: CSAT coletado
    Agent->>EH: csat_received
    EH->>ES: Pull event
    ES->>KQL: Insert into CSAT
    
    KQL->>PBI: Direct Lake/DirectQuery
    Note over PBI: Dashboard atualiza<br/>9 métricas recalculadas
```

---

## Topologia de Rede (Produção)

```mermaid
graph TB
    subgraph "Voice Agent Vendor"
        A[Agent Application]
    end
    
    subgraph "Azure Subscription"
        subgraph "Virtual Network"
            B[Private Endpoint]
        end
        
        C[Event Hub Namespace<br/>Premium SKU]
        D[Managed Identity]
        E[Key Vault<br/>Connection Strings]
    end
    
    subgraph "Microsoft Fabric"
        F[Eventstream<br/>Managed Identity Auth]
        G[Eventhouse<br/>Private Link]
    end
    
    subgraph "Power BI"
        H[Power BI Service]
        I[RLS Rules]
    end
    
    A -->|Public Internet<br/>HTTPS| C
    A -.->|Production:<br/>Private Link| B
    B --> C
    C --> D
    C --> E
    C -->|Managed Identity| F
    F --> G
    G -->|Direct Lake| H
    H --> I
    
    style A fill:#e1f5ff
    style C fill:#fff4e1
    style F fill:#ffe1f5
    style G fill:#f5e1ff
    style H fill:#e1ffe1
```

**Segurança em Produção**:
- ✅ Private Endpoint para Event Hub
- ✅ Managed Identity (sem SAS keys)
- ✅ Private Link para Eventhouse (quando disponível)
- ✅ RLS no Power BI
- ✅ TLS 1.2+ obrigatório

---

## Estrutura de Dados — Power BI Semantic Model

```mermaid
graph LR
    subgraph "Dim Tables"
        A[Dim_Date]
        B[Dim_Channel]
        C[Dim_Intent]
    end
    
    subgraph "Fact Tables"
        D[Conversations]
        E[Turns]
        F[Events]
        G[CSAT]
    end
    
    A -->|1:N| D
    D -->|1:N| E
    D -->|1:N| F
    D -->|1:1| G
    
    subgraph "DAX Measures"
        H[Retenção IA %]
        I[TMR ms]
        J[TMA ms]
        K[Top Acionamentos]
        L[Transbordo %]
        M[Retorno URA %]
        N[Pedido Atendente %]
        O[Taxa Erro %]
        P[CSAT Médio]
    end
    
    D --> H
    E --> I
    E --> J
    E --> K
    F --> L
    F --> M
    F --> N
    F --> O
    G --> P
    
    style A fill:#ffe1e1
    style B fill:#ffe1e1
    style C fill:#ffe1e1
    style D fill:#e1f5ff
    style E fill:#e1f5ff
    style F fill:#e1f5ff
    style G fill:#e1f5ff
    style H fill:#f5ffe1
    style I fill:#f5ffe1
    style J fill:#f5ffe1
    style K fill:#f5ffe1
    style L fill:#f5ffe1
    style M fill:#f5ffe1
    style N fill:#f5ffe1
    style O fill:#f5ffe1
    style P fill:#f5ffe1
```

**Relacionamentos**:
- `Dim_Date [Date] → Conversations [timestamp]` (1:N, cross-filter: both)
- `Conversations [conversationId] → Turns [conversationId]` (1:N, cross-filter: both)
- `Conversations [conversationId] → Events [conversationId]` (1:N, cross-filter: both)
- `Conversations [conversationId] → CSAT [conversationId]` (1:1, cross-filter: single)

---

## Comparação: Plan A vs Plan B

| Aspecto | Plan A (Cosmos DB) | Plan B (Fabric RTI) |
|---------|-------------------|-------------------|
| **Ingestion** | Event Hubs → Function → Cosmos | Event Hubs → Eventstream → Eventhouse |
| **Storage** | Cosmos DB (NoSQL) | Eventhouse (KQL) |
| **Analytics Layer** | Fabric Mirroring or Synapse Link | Native (KQL + OneLake) |
| **Power BI Mode** | Direct Lake via mirroring | Direct Lake native |
| **Peças Móveis** | 4 (EH + Function + Cosmos + Mirroring) | 2 (EH + Fabric) |
| **Time-to-Dashboard** | ~2 horas (replicação) | ~5 min (streaming) |
| **Latência Analytics** | ~2-3 horas | ~5 min - 30 min |
| **Best For** | OLTP + OLAP separados | Analytics near real-time |
| **Custo POC** | ~$200/mês | ~$300/mês |
| **Complexidade** | Maior | Menor |

**Recomendação**: Plan B para **POC e analytics near real-time**. Plan A se precisar de **store transacional separado** ou **multi-consumer** no Cosmos DB.

---

## Escalabilidade e Limites

### Event Hubs

| SKU | Throughput Units | Max Ingress | Max Egress | Retention |
|-----|------------------|-------------|------------|-----------|
| Basic | 1-20 TU | 1 MB/s/TU | 2 MB/s/TU | 1 dia |
| Standard | 1-20 TU | 1 MB/s/TU | 2 MB/s/TU | 7 dias |
| Premium | 1-16 PU | 8 MB/s/PU | 16 MB/s/PU | 90 dias |

**Exemplo**: 
- 1M eventos/dia × 1 KB/evento = 1 GB/dia ≈ 0.01 MB/s → **1 TU suficiente**
- 100M eventos/dia × 1 KB/evento = 100 GB/dia ≈ 1.2 MB/s → **2 TU necessário**

### Eventhouse

| Métrica | Limite | Notas |
|---------|--------|-------|
| Ingestion Rate | Depende do Fabric Capacity | F2: ~2 GB/h, F8: ~20 GB/h |
| Storage | Ilimitado | Custo adicional por TB |
| Query Performance | Sub-segundo para bilhões de eventos | Com particionamento adequado |
| Retention | Configurável (default: 365 dias) | Soft delete policy |

---

## Checklist de Design

### ✅ Considerações de Design Implementadas

- [x] **Particionamento** por `conversationId` (ordem preservada)
- [x] **Consumer Groups** dedicados (Fabric, Monitoring)
- [x] **Schema versionamento** via `eventType`
- [x] **LGPD compliance** (anonimização de IDs, mascaramento de PII)
- [x] **Retention policies** (Event Hub: 7d, Eventhouse: 365d)
- [x] **Idempotência** (conversationId único)
- [x] **Observabilidade** (métricas nativas do Azure)
- [x] **Segurança** (SAS para POC, Managed Identity para produção)

### ⏭️ Próximas Otimizações (Produção)

- [ ] Private Endpoints
- [ ] Multi-region replication (geo-redundancy)
- [ ] Auto-scaling (Event Hub auto-inflate)
- [ ] Alert rules (ingestion failures, latency spikes)
- [ ] Backup/DR strategy
- [ ] Cost optimization (capacity reservations, spot pricing)

---

## Referências

- [Event Hubs Quotas](https://learn.microsoft.com/azure/event-hubs/event-hubs-quotas)
- [Fabric Capacity Metrics](https://learn.microsoft.com/fabric/enterprise/licenses)
- [Eventhouse Best Practices](https://learn.microsoft.com/fabric/real-time-intelligence/best-practices)
- [Power BI Direct Lake Limits](https://learn.microsoft.com/power-bi/enterprise/directlake-overview#known-issues-and-limitations)

---

**Documento**: Diagrama de Arquitetura Detalhado — Plan B  
**Versão**: 1.0  
**Data**: 2026-07-02  
**Status**: ✅ Completo
