# Power BI Configuration — Voice Agent Analytics Dashboard (Plan B)

Guia completo para criar o dashboard de analytics do agente de voz no Power BI, conectando ao **Eventhouse** via Direct Lake ou DirectQuery.

## Arquitetura de Dados

```
┌─────────────────┐         ┌──────────────────┐
│  Eventhouse     │         │    Power BI      │
│  (KQL Database) │ ──────→ │  Semantic Model  │
│                 │ Direct  │  + DAX Measures  │
│ - Conversations │  Lake   │  + Dashboards    │
│ - Turns         │   or    │                  │
│ - Events        │   DQ    │  9 Core Metrics  │
│ - CSAT          │         │  + Drill-through │
└─────────────────┘         └──────────────────┘
```

---

## As 9 Métricas do Escopo

Conforme [`plano-telemetria-analytics.md`](../../docs/plano-telemetria-analytics.md):

1. **Retenção Bruta da IA** — % de conversas resolvidas pela IA
2. **TMR (Tempo Médio de Resposta)** — Latência média por turno
3. **TMA (Tempo Máximo de Atendimento)** — Latência máxima em uma conversa
4. **Principais Acionamentos** — Top N intenções/serviços
5. **Transbordo por Não-Compreensão** — % de eventos `no_comprehension` ou `knowledge_gap`
6. **Retorno ao Menu URA** — % de eventos `returned_to_ura`
7. **Pedido de Atendente** — % de eventos `agent_requested`
8. **Erros** — % de eventos `system_error`
9. **Pesquisa CSAT** — Score médio e distribuição

---

## Parte 1: Conectar ao Eventhouse

### Opção A: Direct Lake (Recomendado — Melhor Performance)

**Pré-requisitos:**
- ✅ OneLake Availability habilitado no Eventhouse
- ✅ Tabelas sincronizadas para OneLake (Delta Parquet)
- ✅ Power BI Desktop ou Power BI Service

**Passos:**

1. **No Power BI Desktop**:
   - Arquivo → Obter Dados → **OneLake data hub**
   - Procure pelo Eventhouse: `VoiceAgentEventhouse`
   - Selecione as tabelas:
     - `Conversations`
     - `Turns`
     - `Events`
     - `CSAT`
   - Clique em **Carregar**

2. **No Power BI Service** (criar diretamente):
   - Workspace → + Novo → **Semantic model**
   - Fonte: **OneLake data hub**
   - Selecione as mesmas tabelas
   - Modo: **Direct Lake**

> ✅ **Vantagem**: Consultas ultra-rápidas, sem import, dados always-on.

### Opção B: DirectQuery via KQL Endpoint

**Quando usar**: Se OneLake não estiver disponível ou precisar consultas KQL customizadas.

**Passos:**

1. **No Power BI Desktop**:
   - Obter Dados → **Azure Data Explorer (Kusto)**
   - Cluster: `https://<eventhouse-uri>.kusto.windows.net`
   - Database: `VoiceAgentDB`
   - Autenticação: **Microsoft Account** ou **Service Principal**

2. **Importar tabelas ou views**:
   ```kql
   // Opção 1: Importar tabelas diretas
   Conversations
   Turns
   Events
   CSAT
   
   // Opção 2: Importar views pré-agregadas (melhor performance)
   ConversationsWithOutcome
   LatencyMetricsByConversation
   ```

3. Selecione **DirectQuery** (não Import) para dados em tempo real.

### Opção C: Import Mode (Não Recomendado — Para POCs Pequenas)

- Use apenas para **< 1M de registros**
- Requisita refresh manual ou agendado
- Perde near real-time

---

## Parte 2: Modelagem de Dados

### 2.1 Relacionamentos

Crie relacionamentos entre tabelas (Power BI pode detectar automaticamente):

```
Conversations (1) ──< Turns (∞)
     conversationId ──── conversationId

Conversations (1) ──< Events (∞)
     conversationId ──── conversationId

Conversations (1) ──< CSAT (1)
     conversationId ──── conversationId
```

**Direção de filtro cruzado:**
- `Conversations → Turns`: Bidirecional (para filtrar turnos por conversa E vice-versa)
- `Conversations → Events`: Bidirecional
- `Conversations → CSAT`: Unidirecional (Conversations → CSAT)

### 2.2 Tabela Calendário (Dim_Date)

Se OneLake não fornecer, crie via DAX:

```dax
Dim_Date = 
ADDCOLUMNS(
    CALENDAR(
        DATE(2026, 1, 1),
        DATE(2027, 12, 31)
    ),
    "Year", YEAR([Date]),
    "Month", FORMAT([Date], "MMM"),
    "MonthNum", MONTH([Date]),
    "Quarter", "Q" & FORMAT([Date], "Q"),
    "WeekNum", WEEKNUM([Date]),
    "DayOfWeek", FORMAT([Date], "ddd"),
    "IsWeekend", IF(WEEKDAY([Date]) IN {1, 7}, TRUE(), FALSE())
)
```

Relacionamento:
```
Dim_Date (1) ──< Conversations (∞)
    [Date]   ──── timestamp (usar apenas a data)
```

---

## Parte 3: Medidas DAX — As 9 Métricas

### 3.1 Retenção Bruta da IA

```dax
// Total de conversas
Total Conversas = COUNTROWS(Conversations)

// Conversas resolvidas pela IA
Conversas Resolvidas IA = 
CALCULATE(
    COUNTROWS(Events),
    Events[eventName] = "conversation_ended",
    Events[details.outcome] = "resolved_by_ai"
)

// Taxa de retenção (%)
🎯 Retenção IA (%) = 
DIVIDE(
    [Conversas Resolvidas IA],
    [Total Conversas],
    0
) * 100
```

### 3.2 TMR — Tempo Médio de Resposta

```dax
// Latência média por turno (ms)
TMR (ms) = AVERAGE(Turns[latencyMs])

// Versão em segundos
TMR (segundos) = [TMR (ms)] / 1000

// TMR por conversa (para drill-down)
TMR por Conversa = 
AVERAGEX(
    VALUES(Conversations[conversationId]),
    CALCULATE(AVERAGE(Turns[latencyMs]))
)
```

### 3.3 TMA — Tempo Máximo de Atendimento

```dax
// Latência máxima em qualquer turno (ms)
TMA (ms) = MAX(Turns[latencyMs])

// TMA por conversa
TMA por Conversa = 
MAXX(
    VALUES(Conversations[conversationId]),
    CALCULATE(MAX(Turns[latencyMs]))
)

// Conversas com TMA > 5 segundos (threshold configurável)
Conversas TMA Alto = 
CALCULATE(
    COUNTROWS(Conversations),
    [TMA por Conversa] > 5000
)
```

### 3.4 Principais Acionamentos (Top N Intenções)

```dax
// Contagem por intenção
Acionamentos por Intent = 
CALCULATE(
    COUNTROWS(Turns),
    ALLEXCEPT(Turns, Turns[intent])
)

// Ranking (para visual de Top N)
Rank Intent = 
RANKX(
    ALL(Turns[intent]),
    [Acionamentos por Intent],
    ,
    DESC,
    Dense
)

// Top 10 Intenções
Top 10 Intents = 
TOPN(
    10,
    SUMMARIZE(
        Turns,
        Turns[intent],
        "Total", COUNTROWS(Turns)
    ),
    [Total],
    DESC
)
```

### 3.5 Transbordo por Não-Compreensão

```dax
// Eventos de não compreensão ou falta de conhecimento
Eventos Não Compreensão = 
CALCULATE(
    COUNTROWS(Events),
    Events[eventName] IN {"no_comprehension", "knowledge_gap"}
)

// Taxa de transbordo (%)
🚨 Transbordo Não Compreensão (%) = 
DIVIDE(
    [Eventos Não Compreensão],
    [Total Conversas],
    0
) * 100
```

### 3.6 Retorno ao Menu URA

```dax
// Eventos de retorno à URA
Eventos Retorno URA = 
CALCULATE(
    COUNTROWS(Events),
    Events[eventName] = "returned_to_ura"
)

// Taxa de retorno (%)
↩️ Retorno URA (%) = 
DIVIDE(
    [Eventos Retorno URA],
    [Total Conversas],
    0
) * 100
```

### 3.7 Pedido de Atendente

```dax
// Eventos de pedido de atendente humano
Eventos Pedido Atendente = 
CALCULATE(
    COUNTROWS(Events),
    Events[eventName] = "agent_requested"
)

// Taxa de pedido (%)
👤 Pedido Atendente (%) = 
DIVIDE(
    [Eventos Pedido Atendente],
    [Total Conversas],
    0
) * 100
```

### 3.8 Erros do Sistema

```dax
// Eventos de erro técnico
Eventos Erro Sistema = 
CALCULATE(
    COUNTROWS(Events),
    Events[eventName] = "system_error"
)

// Taxa de erro (%)
⚠️ Taxa de Erro (%) = 
DIVIDE(
    [Eventos Erro Sistema],
    [Total Conversas],
    0
) * 100

// Erros por tipo (se houver subcategorias em details)
Erros por Tipo = 
SUMMARIZE(
    FILTER(
        Events,
        Events[eventName] = "system_error"
    ),
    Events[details.errorType],
    "Total", COUNTROWS(Events)
)
```

### 3.9 Pesquisa CSAT

```dax
// Score médio (normalizado para escala 0-10)
CSAT Médio = 
AVERAGEX(
    CSAT,
    IF(
        CSAT[scale] = "1-5",
        CSAT[score] * 2,  // Normalizar 1-5 para 0-10
        CSAT[score]
    )
)

// Total de respostas CSAT
Total Respostas CSAT = COUNTROWS(CSAT)

// Distribuição de scores
CSAT Promotores = 
CALCULATE(
    COUNTROWS(CSAT),
    CSAT[scale] = "1-5" && CSAT[score] >= 4
)

CSAT Neutros = 
CALCULATE(
    COUNTROWS(CSAT),
    CSAT[scale] = "1-5" && CSAT[score] = 3
)

CSAT Detratores = 
CALCULATE(
    COUNTROWS(CSAT),
    CSAT[scale] = "1-5" && CSAT[score] <= 2
)

// NPS (Net Promoter Score)
NPS = 
VAR Promotores = DIVIDE([CSAT Promotores], [Total Respostas CSAT], 0)
VAR Detratores = DIVIDE([CSAT Detratores], [Total Respostas CSAT], 0)
RETURN (Promotores - Detratores) * 100
```

---

## Parte 4: Estrutura de Páginas do Dashboard

### 4.1 Página 1: Visão Geral (Overview)

**Cards KPI (no topo):**
- 🎯 Retenção IA (%) — Meta: ≥ 80%
- 📞 Total Conversas — Período selecionado
- ⏱️ TMR (segundos) — Meta: < 3s
- ⭐ CSAT Médio — Meta: ≥ 8.0

**Gráficos:**

1. **Linha do Tempo: Conversas por Dia**
   - X: Dim_Date[Date]
   - Y: [Total Conversas]
   - Slicer: DateRange

2. **Pizza: Desfecho das Conversas**
   - Values: Events[details.outcome]
   - Percentual: [Total Conversas]

3. **Coluna: Top 10 Intenções**
   - X: Turns[intent]
   - Y: [Acionamentos por Intent]
   - Filtro: [Rank Intent] <= 10

4. **Gauge: Taxa de Retenção IA**
   - Value: [Retenção IA (%)]
   - Target: 80
   - Min: 0, Max: 100

**Botões de Navegação:**
- 🔍 Drill-down → Página 2 (Detalhe por Conversa)
- 📊 Análise de Erros → Página 3

### 4.2 Página 2: Detalhe da Conversa (Drill-through)

**Ativado por**: Click em `conversationId` em qualquer visual

**Contexto**: Filtrado para 1 conversa específica

**Cards:**
- ID da Conversa
- Data/Hora de Início
- Canal
- Duração Total
- Total de Turnos
- Desfecho

**Tabela: Transcrição Completa**
```
| Turno | Timestamp | Usuário (Masked) | Agente | Intent | Latência (ms) | Sentimento |
|-------|-----------|------------------|--------|--------|---------------|------------|
| 1     | 14:30:18  | [MASKED]         | Seu saldo é... | saldo | 1250 | neutral |
| 2     | 14:30:25  | [MASKED]         | Posso transferir... | transferencia | 980 | positive |
```

**Linha do Tempo de Eventos:**
- Visual de Timeline mostrando eventos da conversa (start → turns → events → end)

**Gráfico de Latência por Turno:**
- X: turnIndex
- Y: latencyMs

**CSAT (se disponível):**
- Score, comentário, método de coleta

### 4.3 Página 3: Análise de Erros e Transbordo

**Cards:**
- ⚠️ Taxa de Erro (%)
- 🚨 Transbordo Não Compreensão (%)
- ↩️ Retorno URA (%)
- 👤 Pedido Atendente (%)

**Gráficos:**

1. **Treemap: Erros por Tipo**
   - Categoria: Events[details.errorType]
   - Tamanho: COUNTROWS(Events)

2. **Coluna Empilhada: Eventos de Transbordo ao Longo do Tempo**
   - X: Dim_Date[Date]
   - Y: COUNTROWS(Events)
   - Legend: Events[eventName]
   - Filtro: eventName IN {"no_comprehension", "knowledge_gap", "agent_requested", "returned_to_ura"}

3. **Matriz: Intenções com Mais Erros**
   ```
   | Intent          | Não Compreensão | Falta Conhecimento | Total |
   |-----------------|-----------------|-------------------|-------|
   | investimentos   | 45              | 23                | 68    |
   | saque_exterior  | 32              | 18                | 50    |
   ```

---

## Parte 5: Filtros e Slicers

### Slicers Globais (aplicar a todas as páginas)

1. **Período (DateRange)**
   - Campo: Dim_Date[Date]
   - Tipo: Relative Date Range
   - Padrão: Últimos 30 dias

2. **Canal**
   - Campo: Conversations[channel]
   - Multi-select: Sim

3. **Segmento do Cliente**
   - Campo: Conversations[customerSegment]
   - Multi-select: Sim

4. **Fila de Origem**
   - Campo: Conversations[originQueue]
   - Multi-select: Sim

### Slicers Específicos por Página

**Página 1 (Overview):**
- Desfecho da Conversa (Events[details.outcome])

**Página 3 (Erros):**
- Tipo de Evento (Events[eventName])
- Categoria de Evento (Events[eventCategory])

---

## Parte 6: Configurações de Atualização

### Direct Lake (Automático)

- **Atualização**: Gerenciada automaticamente pelo OneLake
- **Latência**: Conforme configurado no Eventhouse (5min - 3h)
- **Ação necessária**: Nenhuma

### DirectQuery (Near Real-Time)

- **Atualização**: On-demand (cada interação do usuário)
- **Latência**: Segundos
- **Ação necessária**: Nenhuma

### Import Mode (Manual)

1. No Power BI Desktop:
   - Home → Refresh
   - Configure refresh schedule no Power BI Service

2. No Power BI Service:
   - Semantic Model → Settings → Scheduled Refresh
   - Frequency: Conforme necessidade (ex: a cada 4 horas)

---

## Parte 7: Row-Level Security (RLS)

Se necessário aplicar restrições por segmento de cliente ou região:

### 7.1 Criar Role

```dax
// Criar role "SegmentoPremium"
[customerSegment] = "Premium"

// Criar role por região
[metadata.region] = USERNAME()
```

### 7.2 Atribuir Usuários

1. Power BI Service → Semantic Model → Security
2. Adicionar usuários/grupos à role
3. Testar com **View as Role**

---

## Parte 8: Publicação

### 8.1 Publicar no Power BI Service

1. Power BI Desktop → Arquivo → Publicar
2. Selecione o workspace: `VoiceAgentAnalytics`
3. Aguarde conclusão

### 8.2 Configurar Refresh (se Import/DirectQuery)

- Semantic Model → Settings → Gateway connection
- Configure scheduled refresh

### 8.3 Criar App

1. Workspace → Create App
2. Adicione o dashboard
3. Publique para usuários finais

---

## Parte 9: Performance Tuning

### 9.1 Otimizar Medidas DAX

- Use **CALCULATE** em vez de **FILTER** quando possível
- Evite **RELATEDTABLE** em medidas de alta frequência
- Prefira **SUMMARIZE** para agregações complexas

### 9.2 Reduzir Colunas Importadas

Se estiver em Import mode:
- Remova colunas não usadas (ex: `payload.metadata` se não for visualizado)
- Use **Query Editor → Remove Columns**

### 9.3 Agregar Dados no Eventhouse

Crie views KQL pré-agregadas para dashboards de alto nível:

```kql
.create materialized-view DailyConversationMetrics on table Conversations {
    Conversations
    | extend date = startofday(timestamp)
    | summarize 
        TotalConversations = count(),
        AvgTurns = avg(totalTurns),
        ResolvedByAI = countif(outcome == "resolved_by_ai")
      by date, channel
}
```

---

## Parte 10: Troubleshooting

### Problema: Direct Lake não conecta

1. ✅ OneLake availability está **habilitado** no Eventhouse?
2. ✅ Tabelas foram **sincronizadas** (status: Available)?
3. ✅ Workspace do Fabric e Power BI estão no **mesmo tenant**?
4. ✅ Permissões: usuário tem **Viewer** no Eventhouse?

### Problema: Medidas DAX retornam valores errados

1. Verifique relacionamentos: estão bidirecionais onde necessário?
2. Use **DAX Studio** para debug: [daxstudio.org](https://daxstudio.org)
3. Valide dados no Eventhouse primeiro (compare com queries KQL)

### Problema: Performance lenta em Direct Lake

1. Reduza número de visuais por página (< 15 recomendado)
2. Use **aggregations** no modelo semântico
3. Considere criar camada agregada no Eventhouse

---

## Próximos Passos

1. ✅ **Power BI conectado** ao Eventhouse
2. ⏭️ **Importar este arquivo** e colar medidas DAX
3. ⏭️ **Criar visualizações** conforme estrutura de páginas
4. ⏭️ **Testar drill-through** e navegação
5. ⏭️ **Publicar** e compartilhar com stakeholders

## Referências

- [Power BI Direct Lake](https://learn.microsoft.com/power-bi/enterprise/directlake-overview)
- [Azure Data Explorer Connector](https://learn.microsoft.com/power-bi/connect-data/desktop-connect-azure-data-explorer)
- [DAX Reference](https://dax.guide)
- [Power BI Best Practices](https://learn.microsoft.com/power-bi/guidance/)
- [OneLake Integration](https://learn.microsoft.com/fabric/onelake/)
