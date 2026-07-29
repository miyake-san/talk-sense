# Infrastructure as Code — Plan B (Fabric RTI Ingestion)

Infrastructure and documentation for the **Plan B** architecture of Voice Agent Analytics using Microsoft Fabric Real-Time Intelligence.

## 📋 Visão Geral

Este diretório contém toda a infraestrutura como código (IaC) e documentação necessária para implementar o **Plano B** de telemetria e analytics do agente de voz, preservado e ampliado na [ADR-004](../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md) e na [ADR-006](../docs/adr/adr-006-end-to-end-foundry-event-hub-fabric.md).

### Arquitetura

```
┌──────────────────┐         ┌───────────────┐         ┌─────────────────┐         ┌──────────────┐
│   Voice Agent    │         │ Azure Event   │         │ Fabric Event-   │         │ Eventhouse   │
│   (Vendor)       │ ──────→ │    Hubs       │ ──────→ │   stream        │ ──────→ │ (KQL DB)     │
│                  │  HTTPS/ │               │  Native │                 │  Direct │              │
│  - Conversations │  AMQP   │ - Namespace   │  Connect│ - Transforms    │  Ingest │ - RawTelem   │
│  - Turns         │         │ - Event Hub   │         │ - Routes        │         │ - Views      │
│  - Events        │         │ - Consumer    │         │                 │         │ - Aggregates │
│  - CSAT          │         │   Groups      │         │                 │         │              │
└──────────────────┘         └───────────────┘         └─────────────────┘         └──────┬───────┘
                                                                                           │
                                                                                           │ Direct Lake
                                                                                           │ or DirectQuery
                                                                                           │
                                                                                  ┌────────▼───────┐
                                                                                  │   Power BI     │
                                                                                  │  Dashboards    │
                                                                                  │  (9 Metrics)   │
                                                                                  └────────────────┘
```

### Componentes

| Componente | Tecnologia | Status IaC | Documentação |
|------------|------------|------------|--------------|
| **Event Hubs** | Azure Event Hubs | ✅ Bicep/Terraform | [`bicep/`](bicep/), [`terraform/`](terraform/) |
| **Eventstream** | Fabric RTI | ⚠️ Manual | [`docs/fabric-configuration.md`](docs/fabric-configuration.md) |
| **Eventhouse** | Fabric RTI (KQL) | ⚠️ Manual | [`docs/fabric-configuration.md`](docs/fabric-configuration.md) |
| **Power BI** | Power BI Service | ⚠️ Manual | [`docs/powerbi-configuration.md`](docs/powerbi-configuration.md) |
| **Message Schema** | JSON | 📄 Spec | [`docs/event-hub-message-format.md`](docs/event-hub-message-format.md) |

---

## 🚀 Quick Start

### Passo 1: Deploy Event Hubs (IaC)

Escolha **Bicep** ou **Terraform**:

#### Opção A: Bicep

```powershell
cd bicep
./deploy.ps1 -Environment dev -Location eastus2
```

#### Opção B: Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Passo 2: Configurar Fabric

Siga o guia detalhado em [`docs/fabric-configuration.md`](docs/fabric-configuration.md):

1. Criar **Eventstream** conectado ao Event Hub
2. Criar **Eventhouse** (KQL Database)
3. Definir **tabelas** e **update policies**
4. Habilitar **OneLake availability**

### Passo 3: Configurar Agente de Voz

Implementar envio de telemetria seguindo [`docs/event-hub-message-format.md`](docs/event-hub-message-format.md):

```javascript
// Exemplo Node.js
const { EventHubProducerClient } = require("@azure/event-hubs");

const connectionString = "Endpoint=sb://..."; // Output do Terraform
const eventHubName = "evh-voiceagent-telemetry";

const producer = new EventHubProducerClient(connectionString, eventHubName);

// Enviar evento
await producer.sendBatch([{
  body: {
    eventType: "conversation_started",
    timestamp: new Date().toISOString(),
    conversationId: "conv-123",
    payload: { /* ... */ }
  },
  partitionKey: "conv-123"
}]);
```

### Passo 4: Criar Dashboards Power BI

Siga [`docs/powerbi-configuration.md`](docs/powerbi-configuration.md):

1. Conectar ao Eventhouse via **Direct Lake** ou **DirectQuery**
2. Criar relacionamentos entre tabelas
3. Importar **medidas DAX** para as 9 métricas
4. Criar páginas do dashboard

---

## 📁 Estrutura de Diretórios

```
infra/
├── bicep/                              # Bicep IaC
│   ├── main.bicep                      # Template principal
│   ├── main.parameters.dev.json        # Parâmetros (dev)
│   └── deploy.ps1                      # Script de deploy
├── terraform/                          # Terraform IaC
│   ├── main.tf                         # Configuração principal
│   ├── terraform.tfvars                # Variáveis
│   └── README.md                       # Documentação Terraform
├── docs/                               # Documentação
│   ├── event-hub-message-format.md     # ⭐ Schema de mensagens JSON
│   ├── fabric-configuration.md         # ⭐ Setup Eventstream/Eventhouse
│   ├── powerbi-configuration.md        # ⭐ Dashboards e DAX
│   └── architecture-diagram.md         # Diagrama detalhado
└── README.md                           # Este arquivo
```

---

## 📊 As 9 Métricas (Dashboard)

Conforme [`plano-telemetria-analytics.md`](../docs/plano-telemetria-analytics.md):

| # | Métrica | Descrição | Fórmula DAX |
|---|---------|-----------|-------------|
| 1 | **Retenção IA** | % conversas resolvidas pela IA | `DIVIDE([Conversas Resolvidas IA], [Total Conversas]) * 100` |
| 2 | **TMR** | Tempo Médio de Resposta por turno | `AVERAGE(Turns[latencyMs]) / 1000` |
| 3 | **TMA** | Tempo Máximo de Atendimento | `MAX(Turns[latencyMs]) / 1000` |
| 4 | **Top Acionamentos** | Top 10 intenções | `TOPN(10, SUMMARIZE(Turns, [intent], ...))` |
| 5 | **Transbordo Não-Compreensão** | % eventos de não compreensão | `DIVIDE([Eventos Não Compreensão], [Total Conversas]) * 100` |
| 6 | **Retorno URA** | % retornos ao menu URA | `DIVIDE([Eventos Retorno URA], [Total Conversas]) * 100` |
| 7 | **Pedido Atendente** | % pedidos de atendente humano | `DIVIDE([Eventos Pedido Atendente], [Total Conversas]) * 100` |
| 8 | **Erros** | % erros de sistema | `DIVIDE([Eventos Erro Sistema], [Total Conversas]) * 100` |
| 9 | **CSAT** | Score médio de satisfação | `AVERAGEX(CSAT, IF([scale] = "1-5", [score] * 2, [score]))` |

---

## 🔒 Segurança e LGPD

### Dados Sensíveis

- ✅ **IDs de Cliente**: Usar **SHA256 hash** (`customerIdAnon`)
- ✅ **Transcrições**: Mascarar ou remover **PII** antes do envio
- ✅ **CSAT Comentários**: Aplicar NER para detectar/remover dados pessoais

### Network Security

**POC/Dev**:
- Event Hub: Public network, SAS authentication

**Produção**:
- Event Hub: **Private Endpoint**, **Managed Identity**
- Fabric: **Private Link** (quando disponível)
- Power BI: **Row-Level Security (RLS)**

### Retention

- **Event Hub**: 7 dias (configurável)
- **Eventhouse**: 365 dias (soft delete)
- **OneLake**: Conforme política do Fabric workspace

---

## 💰 Estimativa de Custos

### Ambiente de Desenvolvimento

| Componente | SKU | Custo Mensal (USD) |
|------------|-----|-------------------|
| Event Hub Namespace | Standard, 1 TU | $25 |
| Event Hub Data Ingress | ~1M events/day | $3 |
| Fabric Capacity | F2 (2 CU) | $260 |
| Power BI Pro | Por usuário | $10/usuário |
| **Total** | | **~$300/mês** |

### Ambiente de Produção

| Componente | SKU | Custo Mensal (USD) |
|------------|-----|-------------------|
| Event Hub Namespace | Premium, zone-redundant | $670 |
| Event Hub Data Ingress | ~10M events/day | $30 |
| Fabric Capacity | F8 (8 CU) | $1,040 |
| Private Endpoints | 2x | $15 |
| Power BI Premium | P1 | $4,995 |
| **Total** | | **~$6,750/mês** |

> Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) para estimativas precisas.

---

## 🛠️ Troubleshooting

### Event Hub: Mensagens não chegam

```bash
# Verificar métricas do Event Hub
az monitor metrics list \
  --resource /subscriptions/.../Microsoft.EventHub/namespaces/evhns-... \
  --metric IncomingMessages \
  --start-time 2026-07-02T00:00:00Z \
  --end-time 2026-07-02T23:59:59Z
```

### Fabric: Eventstream não ingere

1. Verificar **connection string** (copiar novamente do output do Terraform)
2. Verificar **consumer group**: deve ser `fabric-eventstream`
3. Logs: Eventstream → Monitoring → Logs

### Eventhouse: Dados não aparecem

```kql
// Verificar ingestão
.show commands
| where CommandType == "DataIngestPull"
| order by StartedOn desc

// Verificar falhas
.show ingestion failures
| where Table == "RawTelemetry"
| order by Timestamp desc
```

### Power BI: Direct Lake lento

1. Reduzir número de visuais por página (< 15)
2. Criar **agregações** no Eventhouse
3. Usar **DirectQuery** em vez de Direct Lake para queries complexas

---

## 📚 Referências

### Documentação Oficial

- [Azure Event Hubs](https://learn.microsoft.com/azure/event-hubs/)
- [Fabric Real-Time Intelligence](https://learn.microsoft.com/fabric/real-time-intelligence/)
- [Fabric Eventstream](https://learn.microsoft.com/fabric/real-time-intelligence/event-streams/)
- [Eventhouse & KQL](https://learn.microsoft.com/fabric/real-time-intelligence/eventhouse)
- [Power BI Direct Lake](https://learn.microsoft.com/power-bi/enterprise/directlake-overview)

### Documentação do Projeto

- [Plano Principal de Telemetria](../docs/plano-telemetria-analytics.md)
- [Índice de ADRs](../docs/adr/README.md)
- [ADR-004: Métricas em tempo real com Event Hubs e Fabric](../docs/adr/adr-004-real-time-metrics-event-hubs-fabric.md)
- [Prompts Power BI](../docs/powerbi-prompts.md)

---

## 🤝 Suporte

Para dúvidas ou problemas:

1. Revisar documentação em [`docs/`](docs/)
2. Verificar [Issues do projeto](../../issues)
3. Consultar [Microsoft Learn](https://learn.microsoft.com)

---

## ✅ Checklist de Implementação

- [ ] **Deploy IaC** (Bicep ou Terraform)
- [ ] **Configurar Fabric Eventstream** (consumir Event Hub)
- [ ] **Criar Eventhouse** (tabelas + update policies)
- [ ] **Habilitar OneLake** (Direct Lake)
- [ ] **Implementar sender** no agente (SDK Event Hubs)
- [ ] **Testar envio** end-to-end
- [ ] **Conectar Power BI** (Direct Lake ou DirectQuery)
- [ ] **Importar medidas DAX** (9 métricas)
- [ ] **Criar dashboards** (Overview + Drill-through + Erros)
- [ ] **Aplicar RLS** (se necessário)
- [ ] **Publicar** no Power BI Service
- [ ] **Validar** com stakeholders

---

**Status**: ✅ Pronto para POC  
**Última Atualização**: 2026-07-02  
**Autor**: Arquitetura de Dados — Voice Agent Analytics
