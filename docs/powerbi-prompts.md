# Power BI via código — skills disponíveis e prompts prontos

> Responde à pergunta do plano: **"existem skills para gerar dashboards do Power BI via código?"**
> Resposta curta: **sim, parcialmente** — não há uma skill que gere um `.pbix` binário "com um
> clique", mas há (a) **agentes especialistas** que geram o código do modelo/DAX/layout, (b) skills
> que **consultam modelos semânticos já publicados** (validar DAX contra dados reais) e (c) o
> **formato PBIP (código)** — `TMDL` + `PBIR` — que permite versionar e gerar relatórios como texto.
> Abaixo está o inventário e os **prompts prontos** para este projeto.

## 1. Inventário de skills / agentes / MCP relevantes

| Recurso | Tipo | O que faz | Gera dashboard via código? |
|---|---|---|---|
| `power-bi-development:power-bi-data-modeling-expert` | Agente | Modelagem em estrela, relacionamentos, granularidade | Gera **design + TMDL** do modelo |
| `power-bi-development:power-bi-dax-expert` | Agente | Escreve/otimiza **medidas DAX** | Gera **código DAX** |
| `power-bi-development:power-bi-visualization-expert` | Agente | Design de páginas, escolha de visuais, UX, drill-through | Gera **spec de layout / PBIR** |
| `power-bi-development:power-bi-performance-expert` | Agente | Performance (Direct Lake, VertiPaq, DAX lento) | Recomendações + ajustes de código |
| `power-bi-report-design-consultation` | Skill | Consultoria de design de relatório | Guia + spec |
| `power-bi-dax-optimization` | Skill | Otimização de DAX | Código DAX otimizado |
| `power-bi-model-design-review` | Skill | Revisão de modelo | Recomendações |
| `power-bi-performance-troubleshooting` | Skill | Diagnóstico de performance | Recomendações |
| `fabric-iq` (MCP) | Ferramentas | `DiscoverArtifacts`, `GetSemanticModelSchema`, `GenerateQuery`, `ExecuteQuery`, `GetReportMetadata`, `ValueSearch` — **contra modelos já publicados** no Fabric/Power BI | Valida/gera **DAX** contra dados reais |
| `pbi-prompt-builder`, `pbi-reference`, `pbi-portfolio-navigator` (MCAPS-IQ) | Skills | Descobrem _schema_, geram/validam DAX e empacotam prompts `pbi-*.prompt.md` — **para modelos existentes** | Prompts + DAX (não geram o relatório) |

### Conclusão da avaliação
- **Não existe** hoje uma skill que produza o arquivo `.pbix` final automaticamente.
- **Existe** todo o ferramental para o fluxo **code-first**: os agentes `power-bi-development:*`
  geram **TMDL** (modelo), **DAX** (medidas) e **PBIR** (relatório) como texto; o `fabric-iq`
  valida DAX contra os dados já no Fabric.
- **Portanto, o dashboard É gerável via código** pelo formato **PBIP** (abaixo), acelerado por
  esses agentes/skills.

## 2. O caminho "via código": PBIP (TMDL + PBIR)

O **Power BI Project (PBIP)** é o formato aberto e versionável do Power BI Desktop:

```
TalkSense_VoiceAnalytics.pbip
├── TalkSense_VoiceAnalytics.SemanticModel/
│   └── definition/                # TMDL — tabelas, colunas, medidas DAX (texto)
│       ├── model.tmdl
│       ├── tables/FatoConversa.tmdl
│       ├── tables/FatoTurno.tmdl
│       └── ...
└── TalkSense_VoiceAnalytics.Report/
    └── definition/                # PBIR — páginas e visuais (JSON)
        ├── report.json
        └── pages/...
```

- **TMDL** (_Tabular Model Definition Language_): define modelo, tabelas, relacionamentos e **medidas DAX**.
- **PBIR** (_Power BI Enhanced Report format_): define páginas, visuais, filtros e **drill-through** em JSON.
- Ferramentas: Power BI Desktop (habilitar _Preview: Power BI Project (.pbip) save format_),
  **Tabular Editor** (TMDL) e `pbi-tools`.

> **Fluxo recomendado:** (1) usar o agente de modelagem para gerar o TMDL do star schema →
> (2) o agente DAX para as medidas → (3) o agente de visualização para o PBIR das 8 páginas +
> drill-through → (4) abrir o `.pbip` no Power BI Desktop apontando para o Fabric/Synapse →
> (5) validar as medidas com `fabric-iq`.

## 3. Prompts prontos para usar

> Copie/cole nos respectivos agentes. Eles já referenciam o **modelo de dados do plano** e o
> **dicionário de dados** (`sample-data/dicionario-de-dados.md`). Ajuste nomes se necessário.

### Prompt 1 — Modelagem (agente `power-bi-development:power-bi-data-modeling-expert`)

```
Contexto: dashboard de analytics de um agente de voz (atendimento de Investimentos) no Power BI,
alimentado por Azure Cosmos DB via Microsoft Fabric (Direct Lake). Preciso de um star schema.

Tabelas fato:
- FatoConversa (grão = 1 atendimento): conversationId, id_cliente_anon, dataKey, hora,
  tempo_atendimento_seg, latencia_media_ms, latencia_p95_ms, desfecho, retido_pela_ia,
  transferido_humano, motivo_transbordo, fila_transbordo, retornou_menu_ura, pediu_atendente,
  qtd_turnos, qtd_interrupcoes, intencao_primaria, categoria_intencao, subcategoria_intencao,
  kb_hit, teve_erro, tipo_erro, nota_csat, respondeu_csat, sentimento_geral, sentimento_score,
  score_aderencia_persona, url_gravacao.
- FatoTurno (grão = 1 turno): turnoId, conversationId, indice, ts, autor, texto, intencao,
  confianca_nlu, latencia_resposta_ms, sentimento, sentimento_score, interrupcao, kb_artigo_id, fallback.
- FatoEvento (grão = 1 evento): eventId, conversationId, ts, tipo_evento, subtipo, latencia_ms,
  codigo_erro, mensagem_erro, severidade.
- FatoCsat (grão = 1 resposta): csatId, conversationId, id_cliente_anon, nota_csat, comentario_csat, ts.

Dimensões: DimData, DimHora, DimIntencao, DimDesfecho, DimMotivoTransbordo, DimTipoErro, DimFila,
DimClienteAnon, DimSentimento.

Entregue:
1. O diagrama de relacionamentos (1:*, direção de filtro, cardinalidade).
2. O TMDL das tabelas e relacionamentos (formato PBIP), com tipos e chaves.
3. Recomendações de granularidade e de colunas calculadas vs medidas.
Marque url_gravacao como data category = Web URL.
```

### Prompt 2 — Medidas DAX (agente `power-bi-development:power-bi-dax-expert`)

```
Usando o star schema (FatoConversa, FatoTurno, FatoEvento, FatoCsat + dimensões), escreva as
medidas DAX (formato TMDL, prontas para colar) para as 9 métricas do escopo:

1. Retenção Bruta % = DIVIDE(atendimentos com transferido_humano=FALSO, total de atendimentos)
2. TMR (ms) = AVERAGE(FatoTurno[latencia_resposta_ms]) só para autor="ia"; inclua também TMR P50/P90/P95.
3. TMA (s) = AVERAGE(FatoConversa[tempo_atendimento_seg]); formate em mm:ss.
4. Top Acionamentos = contagem de FatoConversa por intencao_primaria (medida de ranking).
5. Transbordo por Não-Compreensão/Sem-Conhecimento = COUNTROWS filtrando motivo_transbordo
   IN {"nao_compreensao","sem_conhecimento"}; e uma medida de clientes distintos.
6. Retornos ao Menu URA = CALCULATE(COUNTROWS, retornou_menu_ura=VERDADEIRO) + clientes distintos.
7. Pedidos de Atendente = CALCULATE(COUNTROWS, pediu_atendente=VERDADEIRO) + clientes distintos.
8. Taxa de Erro % = DIVIDE(atendimentos com teve_erro=VERDADEIRO, total); e contagem de eventos de erro.
9. CSAT Médio = AVERAGE(FatoCsat[nota_csat]); Taxa de Resposta CSAT % = respondeu / total.

Extras: % Sentimento Negativo, Total Atendimentos, Taxa de Transbordo %.
Requisitos: medidas performáticas (evitar iteradores desnecessários), compatíveis com Direct Lake,
com comentários e uma pasta de exibição "KPIs Voz". Explique premissas.
```

### Prompt 3 — Design das páginas + drill-through (agente `power-bi-development:power-bi-visualization-expert`)

```
Projete o relatório Power BI (8 páginas) para o dashboard do agente de voz. Entregue a spec de
layout e, quando possível, o JSON PBIR de cada página.

Páginas:
0. Visão Geral — cartões KPI (Retenção Bruta %, TMR, TMA, Total Atendimentos, Taxa de Transbordo %,
   CSAT Médio, Taxa de Erro %), gráfico de tendência, donut de sentimento, top 10 acionamentos,
   segmentador de período (24h/7d/mês/tudo).
1. Retenção & Transbordo — retenção no tempo; breakdown de transbordo por motivo; tabela "quais
   clientes" (id_cliente_anon, conversationId, motivo). 
2. Latência & Performance — histograma/percentis de TMR (P50/P90/P95) e TMA; latência por intenção.
3. Acionamentos — ranking de intenções (estilo "tracked keywords"), volume por categoria, tendência.
4. Cenários de Experiência — retorno ao menu URA, pedido de atendente, interrupções (contagem + clientes).
5. Erros — erros por tipo/código no tempo; severidade; conversas afetadas.
6. CSAT & Sentimento — distribuição CSAT, média no tempo, taxa de resposta; sentimento geral/por
   intenção/no tempo; correlação CSAT × sentimento.
7. Detalhe da Conversa (PÁGINA DE DRILL-THROUGH por conversationId): cabeçalho com desfecho, TMA,
   TMR, motivo de transbordo, CSAT; MATRIZ da transcrição (autor, hora, texto) a partir de FatoTurno;
   GRÁFICO DE LINHA do sentimento (sentimento_score por indice do turno); latência por turno; KB usada;
   erros; botão/coluna com link para url_gravacao.

Requisitos: configurar drill-through de todas as tabelas com conversationId para a página 7; botão
"Voltar"; tooltips de página com preview da conversa; tema de cores acessível (contraste WCAG AA);
formatação condicional (sentimento negativo em destaque). Baseie-se nas telas de referência de
Conversation Intelligence (overview, tracked keywords e detalhe de chamada com transcrição+sentimento).
```

### Prompt 4 — Validar DAX contra o modelo publicado (MCP `fabric-iq`)

```
Após publicar o modelo no Fabric, use as ferramentas fabric-iq para:
1. DiscoverArtifacts → localizar o semantic model "InterVoiceAnalytics".
2. GetSemanticModelSchema → confirmar tabelas/colunas/medidas.
3. GenerateQuery/ExecuteQuery → validar cada medida (Retenção Bruta %, TMR, TMA, CSAT Médio...)
   retornando um período de amostra e comparando com os números esperados da amostra sintética.
Reporte divergências entre o dashboard e os dados.
```

### Prompt 5 — Performance / Direct Lake (agente `power-bi-development:power-bi-performance-expert`)

```
Revise o modelo InterVoiceAnalytics (Direct Lake sobre Fabric Mirroring do Cosmos DB) para
performance: colunas de alta cardinalidade (texto da transcrição em FatoTurno), estratégia de
_relationship_, uso de medidas vs colunas calculadas, e recomendações de particionamento/refresh.
Aponte medidas DAX com risco de _fallback_ para DirectQuery e como evitá-lo.
```

## 4. Como testar rápido com a amostra sintética

Enquanto o Cosmos/Fabric não está pronto, valide o modelo e as colunas assim:

1. Abra o Power BI Desktop → **Get Data → Text/CSV** e importe os arquivos de
   [`sample-data/output/`](./sample-data/output/) (`conversations.csv`, `turns.csv`, `events.csv`,
   `csat.csv`, `dim_data.csv`).
2. Crie os relacionamentos por `conversationId` (e `dataKey` → `DimData`).
3. Cole as medidas do **Prompt 2** e monte a **Visão Geral** + a página de **Detalhe da Conversa**.
4. Confira se as colunas do CSV cobrem todos os visuais — o dicionário de dados lista cada coluna.
