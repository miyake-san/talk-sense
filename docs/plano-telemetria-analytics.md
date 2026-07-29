# Plano de Telemetria & Analytics — TalkSense (Voice Agent Analytics)

> **Projeto TalkSense** — Compreensão inteligente das chamadas. 
> Plataforma de analytics para agentes de voz do setor financeiro. Este plano descreve **como 
> capturar a telemetria do agente de voz, enviá-la para uma base de dados e consumi-la no Power BI** 
> para montar um dashboard executivo com visões gerais e páginas de _drill-down_ até o detalhe de 
> cada conversa (transcrição + sentimento).

- **Projeto:** TalkSense (Open Source Reference Implementation)
- **Autor:** Time de Arquitetura / Analytics
- **Status:** Analytics reference implemented; target architecture proposed
- **Versão:** 1.0
- **Licença:** MIT
- **Fontes de referência:** Boas práticas de dashboards de _contact center_ / _voice AI_, 
  Azure Well-Architected Framework, Microsoft Fabric Real-Time Intelligence best practices.

> Este documento registra o plano analítico original. As decisões de arquitetura de destino e
> suas substituições estão no [índice de ADRs](./adr/README.md).

---

## 1. Objetivo

Estruturar a esteira de dados que permite **acompanhar a performance do agente de voz** em instituições
financeiras por meio de 9 métricas de negócio críticas, disponibilizando-as em um **dashboard Power BI** com:

1. Uma **visão geral** (KPIs executivos + tendências).
2. Diversas **páginas de _drill-down_** por dimensão (retenção/transbordo, latência, acionamentos,
   cenários de experiência, erros, CSAT/sentimento).
3. Uma página de **detalhe da conversa** acessível por _link/drill-through_ a partir de um
   `conversationId`, exibindo **transcrição completa**, **linha do tempo de sentimento**, latência
   por turno, motivo de transbordo, CSAT e erros — tudo em um único lugar (padrão da tela
   `imagem.png`).

## 2. Métricas exigidas (escopo) → definição, fórmula e origem do dado

| # | Métrica (escopo) | Definição operacional | Fórmula (medida) | Campo(s) de origem |
|---|---|---|---|---|
| 1 | **Retenção bruta da IA** | Atendimentos que a IA **não** transbordou para fila de atendimento humano | `DIVIDE( COUNTROWS(retidos), COUNTROWS(total) )` onde `retido = transferido_humano = FALSO` | `retido_pela_ia` (bool), `transferido_humano` (bool) |
| 2 | **TMR — Tempo Médio de Resposta** | Latência média da IA por turno (fim da fala do cliente → início da resposta da IA) | `AVERAGE(FatoTurno[latencia_resposta_ms])` (+ P50/P90/P95) | `latencia_resposta_ms` (por turno da IA) |
| 3 | **TMA — Tempo Médio de Atendimento** | Duração média do atendimento conduzido pela IA (até encerrar ou transbordar) | `AVERAGE(FatoConversa[tempo_atendimento_seg])` | `tempo_atendimento_seg` = `fim_ts − inicio_ts` |
| 4 | **Principais acionamentos** | Ranking dos motivos/assuntos pelos quais o cliente acionou a IA | `COUNTROWS() GROUP BY intencao_primaria` | `intencao_primaria`, `categoria_intencao`, `subcategoria_intencao` |
| 5 | **Transbordo por não-compreensão / falta de conhecimento** | Quantos e **quais** clientes foram para o humano por a IA não entender ou não saber | `FILTER(motivo_transbordo IN {"nao_compreensao","sem_conhecimento"})` | `motivo_transbordo`, `id_cliente_anon` |
| 6 | **Retorno ao menu URA** | Quantos e quais clientes voltaram para o menu de opções (digitou 0 ou pediu voltar) | `FILTER(retornou_menu_ura = VERDADEIRO)` | `retornou_menu_ura` (bool), `gatilho_retorno_ura` |
| 7 | **Pedido para falar com atendente** | Quantos e quais clientes pediram atendimento humano/especialista | `FILTER(pediu_atendente = VERDADEIRO)` | `pediu_atendente` (bool) |
| 8 | **Erros** | Falhas/instabilidades que afetaram o atendimento (redirecionam para humano) | `COUNTROWS(FatoEvento[tipo_evento]="erro")` e/ou `teve_erro = VERDADEIRO` | `teve_erro` (bool), `tipo_erro`, `codigo_erro` |
| 9 | **Pesquisa CSAT** | Satisfação do cliente pós-atendimento | `AVERAGE(FatoCsat[nota_csat])`, distribuição e taxa de resposta | `nota_csat` (1–5), `comentario_csat`, `respondeu_csat` |

### 2.1 Critérios de qualidade da IA (offline eval — do mesmo escopo)

Além das 9 métricas operacionais, o escopo lista critérios de avaliação da IA. Eles são medidos
majoritariamente em processo de _evaluation_ (amostragem + revisão humana / LLM-as-judge), porém
já reservamos campos no modelo para reportá-los no mesmo dashboard:

| Critério | Campo no modelo | Como é preenchido |
|---|---|---|
| Precisão (respostas corretas) | `flag_precisao` | Eval offline / rótulo humano |
| Taxa de compreensão (intenção correta) | `flag_compreensao`, `confianca_nlu` | NLU + eval |
| Taxa de alucinações | `flag_alucinacao` | Eval offline (groundedness) |
| Cobertura de conhecimento | `kb_hit` (KB respondeu?), `flag_cobertura` | Sinal do RAG + eval |
| Desambiguador | `usou_desambiguacao` (bool) | Telemetria do agente |
| Aderência ao escopo (persona/voz/experiência) | `score_aderencia_persona` (0–1) | Eval de conformidade |

> As métricas 1–9 são obrigatórias para o MVP. Os critérios de qualidade acima são **desejáveis**
> e podem entrar em uma página secundária "Qualidade da IA".

## 3. Arquitetura da solução

```
┌──────────────────────────┐   eventos (turno/conversa)   ┌───────────────────────┐
│  Agente de Voz (vendor)  │ ───────────────────────────► │  Camada de Ingestão   │
│  ASR · NLU/LLM · TTS     │   JSON via HTTPS/SDK          │  Azure Event Hubs /   │
│  Orquestração + Barge-in │                              │  API de telemetria    │
└──────────────────────────┘                              └───────────┬───────────┘
                                                                       │ (função/stream processor)
                                                                       ▼
                                                          ┌────────────────────────┐
                                                          │  Base de dados (OLTP)  │
                                                          │  Azure Cosmos DB NoSQL │
                                                          │  containers:           │
                                                          │   • conversations      │
                                                          │   • events             │
                                                          │   • csat               │
                                                          └───────────┬────────────┘
                                                                      │ HTAP (sem ETL)
                                        ┌─────────────────────────────┴──────────────────────────┐
                                        ▼                                                         ▼
                        ┌───────────────────────────────┐                       ┌────────────────────────────────┐
                        │  Microsoft Fabric (Mirroring) │  (opção recomendada)  │  Synapse Link (Analytical      │
                        │  OneLake → SQL analytics EP    │                       │  Store) → Synapse Serverless   │
                        └───────────────┬───────────────┘                       └────────────────┬───────────────┘
                                        └───────────────────────┬─────────────────────────────────┘
                                                                ▼
                                              ┌────────────────────────────────┐
                                              │  Modelo semântico Power BI      │
                                              │  (star schema + medidas DAX)    │
                                              └────────────────┬───────────────┘
                                                               ▼
                                              ┌────────────────────────────────┐
                                              │  Dashboard Power BI             │
                                              │  Overview + drill-downs +       │
                                              │  drill-through da conversa      │
                                              └────────────────────────────────┘
```

### 3.1 Componentes

- **Agente de voz (fornecedor):** emite eventos de telemetria durante a conversa (por turno) e um
  documento consolidado no encerramento. É o **produtor** dos dados.
- **Camada de ingestão:** endpoint de coleta (Azure Event Hubs, Kafka ou API HTTPS). Uma função de
  processamento (Azure Functions / Stream Analytics) normaliza e grava nos _containers_ do Cosmos DB.
- **Base de dados (OLTP):** **Azure Cosmos DB for NoSQL** para estado operacional (ver
  [ADR-003](./adr/adr-003-conversation-knowledge-mining-pipeline.md) e
  [ADR-006](./adr/adr-006-end-to-end-foundry-event-hub-fabric.md)).
- **Camada analítica (serving):** expõe os dados para BI **sem impactar** o _store_ transacional:
  - **Recomendado:** _Microsoft Fabric Mirroring_ do Cosmos DB → OneLake → _SQL analytics endpoint_ →
    Power BI em **Direct Lake** (baixa latência, sem ETL).
  - **Alternativa:** _Azure Synapse Link_ (analytical store) → Synapse Serverless SQL → Power BI (Import/DirectQuery).
- **Power BI:** modelo semântico em estrela + medidas DAX + páginas do dashboard.

### 3.2 Estratégia de emissão de telemetria

| Momento | O que é enviado | Destino |
|---|---|---|
| Início da sessão | `session_start` (id, cliente anonimizado, canal, timestamp) | `events` |
| A cada turno | `user_utterance`, `asr_result`, `nlu_intent`, `kb_query`, `ai_response` (com `latencia_resposta_ms`), `barge_in` | `events` + array `turns[]` |
| Transbordo | `transfer_initiated` / `transfer_completed` (com `motivo_transbordo`, `fila`) | `events` + conversa |
| Retorno URA / pedido atendente | `ura_return`, `agent_requested` | `events` + conversa |
| Erro | `error` (código, mensagem, severidade) | `events` + `teve_erro` |
| Encerramento | **documento consolidado** da conversa (métricas já pré-calculadas: TMR médio, TMA, desfecho, sentimento, intenção primária) | `conversations` |
| Pós-atendimento | resposta da **pesquisa CSAT** (nota, comentário) vinculada por `conversationId` | `csat` |

> **Por que consolidar no encerramento?** Pré-calcular TMR/TMA/desfecho/sentimento no documento da
> conversa simplifica o modelo do Power BI (menos _joins_ pesados) e mantém o detalhe granular no
> `events`/`turns[]` para o _drill-through_.

## 4. Modelo de dados (documentos Cosmos DB)

### 4.1 Container `conversations` (grão = 1 atendimento)

Documento **denormalizado**: resumo da conversa + array `turns[]` (transcrição) para viabilizar o
_drill-through_ de forma direta. Ver exemplo completo em
[`sample-data/output/conversation_sample.json`](./sample-data/output/conversation_sample.json).

Campos principais (ver [dicionário de dados](./sample-data/dicionario-de-dados.md) para a lista completa):

- **Identificação:** `conversationId` (PK lógica p/ drill-through), `sessionId`, `id_cliente_anon`,
  `segmento`, `canal`.
- **Tempo:** `inicio_ts`, `fim_ts`, `data`, `hora`, `dia_semana`, `tempo_atendimento_seg` (**TMA**).
- **Desfecho:** `desfecho` (enum), `retido_pela_ia` (**#1**), `transferido_humano`,
  `motivo_transbordo` (**#5**), `fila_transbordo`, `retornou_menu_ura` (**#6**), `pediu_atendente` (**#7**).
- **Interação:** `qtd_turnos`, `qtd_interrupcoes` (barge-in), `latencia_media_ms` (**#2/TMR**),
  `latencia_p95_ms`.
- **Assunto:** `intencao_primaria` (**#4**), `categoria_intencao`, `subcategoria_intencao`,
  `kb_hit`, `kb_artigos[]`.
- **Erros:** `teve_erro` (**#8**), `tipo_erro`, `codigo_erro`.
- **Satisfação/sentimento:** `nota_csat` (**#9**), `respondeu_csat`, `sentimento_geral`,
  `sentimento_score`, `sentimento_inicio`, `sentimento_fim`.
- **Qualidade:** `flag_precisao`, `flag_compreensao`, `flag_alucinacao`, `flag_cobertura`,
  `usou_desambiguacao`, `score_aderencia_persona`.
- **Mídia:** `url_gravacao`, `transcricao_disponivel`.
- **Transcrição embutida:** `turns[]` → `{ indice, ts, autor, texto, intencao, confianca_nlu,
  latencia_resposta_ms, sentimento, sentimento_score, interrupcao, kb_artigo_id, fallback }`.

### 4.2 Container `events` (grão = 1 evento de telemetria)

Telemetria bruta de alta frequência (para funil, erros e auditoria). **TTL** sugerido de 90 dias
(o resumo em `conversations` fica retido por mais tempo). Partition key `/conversationId`.

Campos: `eventId`, `conversationId`, `ts`, `tipo_evento`, `subtipo`, `latencia_ms`, `payload`,
`codigo_erro`, `mensagem_erro`, `severidade`.

### 4.3 Container `csat` (grão = 1 resposta de pesquisa)

`csatId`, `conversationId`, `id_cliente_anon`, `nota_csat` (1–5), `comentario_csat`, `ts`, `canal_pesquisa`.
(Pode ser embutido em `conversations`; mantido separado por chegar de forma assíncrona.)

### 4.4 Escolha da _partition key_

| Container | Partition key sugerida | Justificativa |
|---|---|---|
| `conversations` | `/id_cliente_anon` | Boa cardinalidade, agrupa o histórico do cliente (útil p/ métricas #5/#6/#7 "quais clientes"). |
| `events` | `/conversationId` | _Point reads_ por conversa (drill-through) e escrita distribuída. |
| `csat` | `/conversationId` | Junção 1:1 com a conversa. |

> Com Fabric Mirroring/Synapse Link, a _partition key_ transacional **não** limita as consultas de
> BI (a camada analítica é colunar e independente).

## 5. Privacidade e conformidade (LGPD)

O escopo pede identificar **"quais clientes"** foram transbordados/retornaram/pediram atendente.
Como se trata de clientes PF, aplicar **minimização de dados**:

- **Não** armazenar CPF/nome em claro no _store_ analítico. Usar `id_cliente_anon` = _hash_
  determinístico (ex.: HMAC-SHA256 do CPF com _salt_ gerenciado em Key Vault), que permite
  agrupar/contar por cliente sem expor o dado.
- Manter o _de-para_ (hash → cliente) apenas no sistema de origem/CRM, acessível sob permissão.
- Transcrições podem conter PII → aplicar **mascaramento** (ex.: números de conta) na ingestão e
  restringir acesso à página de detalhe por RLS (Row-Level Security) no Power BI.
- Definir **retenção**: eventos brutos 90 dias; resumos/CSAT conforme política do Inter.

## 6. Modelo semântico Power BI (esquema em estrela)

A camada analítica expõe **views achatadas** (o JSON aninhado do Cosmos é explodido em SQL/notebook):

**Tabelas fato**
- `FatoConversa` (1 linha/conversa) → base de #1, #3, #4, #5, #6, #7, #8, #9.
- `FatoTurno` (1 linha/turno) → base de **#2 (TMR)**, transcrição e linha do tempo de sentimento.
- `FatoEvento` (1 linha/evento) → funil e **#8 (erros)** detalhado.
- `FatoCsat` (1 linha/resposta) → **#9**.

**Tabelas dimensão**
- `DimData` (calendário), `DimHora`, `DimIntencao` (acionamento/categoria/subcategoria),
  `DimDesfecho`, `DimMotivoTransbordo`, `DimTipoErro`, `DimFila`, `DimClienteAnon`, `DimSentimento`.

**Relacionamentos:** `FatoConversa[conversationId]` 1→* `FatoTurno`, `FatoEvento`, `FatoCsat`;
fatos → dimensões por chaves (`dataKey`, `intencaoKey`, etc.).

**Principais medidas DAX** (nomes em `docs/powerbi-prompts.md`):
`Retenção Bruta %`, `TMR (ms)`, `TMR P95`, `TMA (s)`, `Total Atendimentos`, `Taxa de Transbordo %`,
`Transbordo por Não-Compreensão`, `Retornos ao Menu URA`, `Pedidos de Atendente`, `Taxa de Erro %`,
`CSAT Médio`, `Taxa de Resposta CSAT %`, `% Sentimento Negativo`.

## 7. Estrutura do dashboard (páginas)

Inspirado nas telas de referência (`imagem (1).png` = _Team overview_; `imagem (2/3).png` =
_tracked keywords_; `imagem.png` = detalhe da chamada com transcrição + sentimento).

| # | Página | Conteúdo principal | Drill / Link |
|---|---|---|---|
| 0 | **Visão Geral** | Cartões KPI (Retenção Bruta, TMR, TMA, Total, Transbordo %, CSAT, Erro %). Tendência temporal. Donut de sentimento. Top 10 acionamentos. Filtro de período (24h/7d/mês/tudo). | Botões p/ demais páginas |
| 1 | **Retenção & Transbordo** | Retenção ao longo do tempo; _breakdown_ do transbordo por motivo (#5 não-compreensão/sem-conhecimento, #7 atendente, #8 erro); tabela "quais clientes". | Drill-through → Detalhe da Conversa |
| 2 | **Latência & Performance (TMR/TMA)** | Histograma/percentis de TMR (P50/P90/P95) e TMA; latência por intenção; tendência. | Drill por intenção |
| 3 | **Acionamentos (Intenções)** | Ranking de acionamentos (padrão _tracked keywords_), volume por categoria/subcategoria, tendência, conversas relevantes. | Drill-through → Detalhe |
| 4 | **Cenários de Experiência** | #6 Retorno ao menu URA, #7 Pedido de atendente, interrupções (barge-in): contagem, quais clientes, tendência. | Drill-through → Detalhe |
| 5 | **Erros** | #8 Erros por tipo/código ao longo do tempo; conversas afetadas; severidade. | Drill-through → Detalhe |
| 6 | **CSAT & Sentimento** | Distribuição CSAT, média no tempo, taxa de resposta; sentimento geral/por vendedor-intenção/no tempo (padrão `imagem (1).png` §3); correlação CSAT × sentimento. | Drill por intenção |
| 7 | **Detalhe da Conversa** _(drill-through)_ | Filtrada por `conversationId`: cabeçalho (desfecho, TMA, TMR, motivo transbordo, CSAT), **transcrição turno-a-turno**, **linha do tempo de sentimento**, latência por turno, KB usada, erros, link da gravação. | Alvo do drill-through de todas as páginas |

### 7.1 Como implementar o "clicar no ID e ver tudo" (requisito central)

No Power BI o padrão é combinar:

1. **Página de _drill-through_** (`Detalhe da Conversa`) com o campo `conversationId` na área de
   _Drill-through_ + botão "Voltar". Clicar com o botão direito em qualquer linha com
   `conversationId` → **Drill through** → abre a página filtrada por aquela conversa.
2. **Botão de navegação** com ação _Drill through_ para um clique direto.
3. **Coluna de URL** (data category = _Web URL_) para links externos: `url_gravacao` (áudio) e link
   do CRM/fila. A transcrição é renderizada por uma **matriz** (`autor`, `hora`, `texto`) e o
   sentimento por um **gráfico de linha** de `sentimento_score` por `indice` do turno.
4. **Tooltip de página** para _preview_ ao passar o mouse sobre um `conversationId`.

## 8. Roadmap de implementação

| Fase | Entregável | Descrição |
|---|---|---|
| 0 | **Contrato de telemetria** | Fechar com o fornecedor o _schema_ dos eventos (esta doc + `dicionario-de-dados.md`). |
| 1 | **Provisionar dados** | Cosmos DB (containers + partition keys + TTL) e camada de ingestão. |
| 2 | **Camada analítica** | Habilitar Fabric Mirroring (ou Synapse Link) + views achatadas. |
| 3 | **Amostra sintética** | Carregar `sample-data/` para validar o modelo e as colunas no Power BI (**já entregue aqui**). |
| 4 | **Modelo + Dashboard** | Star schema, medidas DAX, 8 páginas, drill-through. Ver prompts em `powerbi-prompts.md`. |
| 5 | **Segurança & governança** | RLS, mascaramento de PII, retenção, permissões. |
| 6 | **Validação** | Comparar métricas do dashboard com amostras reais; ajustar. |

## 9. Riscos & decisões em aberto

- **Persistência de destino:** Cosmos DB para estado operacional conforme
  [ADR-003](./adr/adr-003-conversation-knowledge-mining-pipeline.md), e Eventhouse/OneLake para
  analytics conforme [ADR-004](./adr/adr-004-real-time-metrics-event-hubs-fabric.md).
- **PII em transcrições:** exige mascaramento + RLS antes de expor a página de detalhe amplamente.
- **CSAT assíncrono:** taxa de resposta baixa é comum; reportar sempre `Taxa de Resposta CSAT %`.
- **"Retenção bruta" vs "líquida":** o escopo pede a **bruta** (sem descontar recontatos). Deixar
  claro na definição do KPI para evitar interpretação equivocada.
- **Ambiente de nuvem:** o vendor pode ser AWS-native (a KB usa `s3_faq_integration`).
  A integração e os limites de responsabilidade são tratados na
  [ADR-006](./adr/adr-006-end-to-end-foundry-event-hub-fabric.md).

## 10. Artefatos deste plano

| Artefato | Caminho |
|---|---|
| Este plano | `docs/plano-telemetria-analytics.md` |
| Índice de ADRs | `docs/adr/README.md` |
| Roadmap de implementação | `docs/adr/implementation-roadmap.md` |
| Skills PBI + prompts | `docs/powerbi-prompts.md` |
| Dicionário de dados | `docs/sample-data/dicionario-de-dados.md` |
| Gerador de dados sintéticos | `docs/sample-data/gerar_dados_sinteticos.py` |
| Amostras (CSV/JSON) | `docs/sample-data/output/` |
