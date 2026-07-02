# ADR-001 — Base de dados de analytics para Voice Agent Telemetry (consumo via Power BI)

- **Projeto:** TalkSense (Compreensão inteligente das chamadas)
- **Status:** Accepted (implementado no Plano B com Fabric RTI)
- **Data:** 2026-07-01
- **Decisores:** Arquitetura de Dados / Analytics / Segurança
- **Relacionado:** [`plano-telemetria-analytics.md`](../plano-telemetria-analytics.md) · [ADR-002](./adr-002-ingestao-fabric-rti-eventhouse.md) (ingestão/analytics via Fabric RTI)

## Contexto

Plataformas de analytics para agentes de voz no setor financeiro precisam persistir a telemetria de 
atendimentos (conversas, turnos, eventos, CSAT) em uma **base de dados adequada** e disponibilizá-la para
**leitura no Power BI**, gerando um dashboard com visão geral e _drill-down_ até o detalhe de cada
conversa (transcrição + sentimento).

Características da carga:
- **Dados semiestruturados** (documentos JSON com transcrição aninhada, tamanho variável por conversa).
- **Escrita orientada a evento** (alto volume de eventos por turno; um documento consolidado por conversa).
- **Leitura analítica** (agregações por período/intenção/desfecho) + **_point read_** (detalhe de 1 conversa).
- Requisito **explícito** de **consumo no Power BI** com _drill-through_ e links.

O escopo permite escolher entre **Cosmos DB** ou **DocumentDB**. Interpretamos as opções como:

- **A) Azure Cosmos DB for NoSQL** (Microsoft Azure) — store transacional com mirroring para Fabric.
- **B) Microsoft Fabric Eventhouse** (KQL Database) — store analítico nativo para telemetria estruturada.
- **C) Hybrid approach** — Event Hubs para ingestão + escolha de store downstream.

(Nota: A decisão final do projeto TalkSense foi o **Plano B**: Event Hubs → Fabric Eventstream → Eventhouse,
documentado em ADR-002, que oferece melhor time-to-dashboard e analytics nativo.)

## Critérios de decisão

1. **Integração nativa com Power BI** (peso alto — requisito do projeto).
2. **Analytics sem impactar o _store_ transacional** (HTAP / separação OLTP × OLAP).
3. **Aderência a documentos JSON aninhados** (transcrição embutida).
4. **Esforço operacional / _time-to-dashboard_** na POC.
5. **Custo** na escala de POC.
6. **Segurança/LGPD** (mascaramento, RLS, gestão de chaves).
7. **Aderência ao ecossistema já em uso** (AWS do vendor × Azure/Power BI do consumidor).

## Opções avaliadas

### Opção A — Azure Cosmos DB for NoSQL  ✅ (recomendada)

**Prós**
- **Conector nativo do Power BI** para Cosmos DB (API NoSQL).
- Caminho HTAP maduro para BI **sem ETL** e **sem consumir RUs** do transacional:
  - **Microsoft Fabric Mirroring** → OneLake → _SQL analytics endpoint_ → Power BI em **Direct Lake**
    (recomendado; baixa latência, _setup_ simples).
  - **Azure Synapse Link** (analytical store colunar) → Synapse Serverless SQL → Power BI.
- Ótimo para **documentos JSON aninhados** (transcrição embutida) — a camada analítica achata o JSON.
- _Point read_ barato por `id`/partition key (detalhe da conversa) + agregações na camada colunar.
- Segurança: Private Link, Managed Identity, integração com Key Vault, RLS aplicado no Power BI.

**Contras**
- Requer conta Azure (o vendor da IA pode ser AWS).
- Analytical store/mirroring adiciona custo de storage/compute analítico.
- Modelagem de _partition key_ e RU exige atenção para não encarecer.

### Opção B — Amazon DocumentDB (compatível com MongoDB)

**Prós**
- Compatível com MongoDB; natural se **toda** a stack do vendor for AWS.
- Boa aderência a documentos JSON; escala gerenciada na AWS.

**Contras**
- **Sem conector _first-party_ do Power BI.** Exige uma destas pontes, todas com atrito:
  - ODBC/JDBC + MongoDB BI Connector (sem DirectQuery real, performance limitada), **ou**
  - Pipeline **ETL/ELT** para um _store_ suportado (S3 + Athena, Redshift, Azure SQL) antes do BI.
- **Não há HTAP nativo** para BI: analytics tende a exigir cópia/transformação → mais peças móveis,
  mais latência e mais manutenção na POC.
- Conectores de terceiros (Simba/CData/Progress) → custo, risco de compliance e quebras por _schema_.
- _Time-to-dashboard_ maior; distância maior do ecossistema Power BI.

### Comparativo

| Critério | A) Azure Cosmos DB | B) Amazon DocumentDB |
|---|---|---|
| Conector nativo Power BI | ✅ Sim (NoSQL) | ❌ Não (ODBC/3rd-party/ETL) |
| HTAP sem ETL (Fabric/Synapse) | ✅ Sim | ❌ Não |
| JSON aninhado (transcrição) | ✅ Ótimo | ✅ Ótimo |
| Esforço até o dashboard | 🟢 Baixo | 🔴 Alto |
| Direct Lake / near real-time | ✅ Sim | ⚠️ Via cópia/ETL |
| Custo na POC | 🟡 Médio | 🟡 Médio + pipeline |
| Ecossistema do vendor (AWS) | ⚠️ Fora | ✅ Dentro |
| Ecossistema do consumidor (Power BI/Azure) | ✅ Dentro | ⚠️ Fora |

## Decisão

**Adotar a Opção A — Azure Cosmos DB for NoSQL**, servindo o Power BI pela camada analítica via
**Microsoft Fabric Mirroring** (preferencial) ou **Azure Synapse Link** (alternativa), com Power BI
em **Direct Lake**/Import.

### Justificativa
O requisito central é **consumir no Power BI** com _drill-down_ e links. O Azure Cosmos DB é a única
opção com **integração nativa + HTAP sem ETL**, entregando o menor _time-to-dashboard_ e a melhor
experiência de _near real-time_ para a POC, mantendo total aderência a documentos JSON aninhados.
O Amazon DocumentDB seria competitivo **apenas** se o consumo fosse fora do Power BI ou se a stack
inteira (inclusive analytics) permanecesse na AWS — o que não é o caso.

## Consequências

**Positivas**
- Dashboard operacional rapidamente; caminho oficial e suportado Cosmos → Fabric/Synapse → Power BI.
- Separação OLTP/OLAP preserva a performance do atendimento em tempo real.
- Base para evoluir de POC a produção (RLS, Private Link, retenção, alertas).

**Negativas / mitigação**
- Se o vendor for AWS-only, é preciso **exportar a telemetria para o Azure** (ingestão via Event Hubs
  ou _batch_). → _Mitigação:_ contrato de telemetria (HTTPS/SDK) apontando para a ingestão Azure; se
  necessário, _relay_ a partir de S3.
- Custo do analytical store/mirroring. → _Mitigação:_ TTL nos eventos brutos, _mirroring_ só das
  coleções necessárias, granularidade de sincronização adequada.
- Governança LGPD. → _Mitigação:_ `id_cliente_anon` (hash), mascaramento de PII na ingestão, RLS na
  página de detalhe, chaves no Key Vault.

## Alternativa de contingência

Caso haja restrição corporativa para uso de Azure na POC e a stack precise permanecer em AWS,
adotar Amazon DocumentDB **com** um _pipeline_ explícito **DocumentDB → S3 (Parquet) → Athena/Redshift
→ Power BI**, assumindo o custo/latência adicionais. Reavaliar esta ADR se esse cenário se concretizar.
