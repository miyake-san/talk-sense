# Dicionário de Dados — TalkSense (Voice Agent Analytics)

Este dicionário descreve **todas as colunas** dos arquivos de amostra em [`output/`](./output/).
Serve para: (a) o **contrato de telemetria** com o fornecedor do agente de voz e (b) orientar a
modelagem no Power BI (quais colunas cada visual precisa).

> ⚠️ **Dados 100% sintéticos e anonimizados**, gerados por [`gerar_dados_sinteticos_talksense.py`](./gerar_dados_sinteticos_talksense.py).
> Nenhum dado real de cliente. `customerIdAnon` usa hash SHA256 somente nos dados sintéticos;
> identificadores reais exigem a pseudonimização e os controles da [ADR-007](../adr/adr-007-security-privacy-responsible-ai.md).
> A conformidade de produção depende de implementação e revisão organizacional. Projeto open-source:
> **TalkSense** (Compreensão inteligente das chamadas).

## Mapa arquivo → tabela Power BI

| Arquivo | Tabela no modelo | Grão | Métricas atendidas |
|---|---|---|---|
| `conversations.csv` | `FatoConversa` | 1 atendimento | #1, #3, #4, #5, #6, #7, #8, #9 |
| `turns.csv` | `FatoTurno` | 1 turno (transcrição) | **#2 (TMR)**, transcrição, sentimento por turno |
| `events.csv` | `FatoEvento` | 1 evento de telemetria | #8 (erros), funil |
| `csat.csv` | `FatoCsat` | 1 resposta de pesquisa | **#9 (CSAT)** |
| `dim_data.csv` | `DimData` | 1 dia | eixo de tempo de todas as métricas |
| `conversation_sample.json` | (documento Cosmos) | 1 atendimento aninhado | exemplo do formato de origem |

Relacionamentos: `FatoConversa[conversationId]` 1→* `FatoTurno` / `FatoEvento` / `FatoCsat`;
`Fato*[dataKey]` * →1 `DimData[dataKey]`.

---

## 1. `conversations.csv` → `FatoConversa`

| Coluna | Tipo | Descrição | Uso no dashboard |
|---|---|---|---|
| `conversationId` | GUID (texto) | **Chave** do atendimento. Alvo do _drill-through_. | Chave / link p/ Detalhe |
| `sessionId` | texto | Id da sessão de voz. | Rastreio |
| `id_cliente_anon` | texto | Cliente **anonimizado** (`CLI-<hash>`). | "Quais clientes" (#5/#6/#7), distintos |
| `segmento` | texto | Segmentação (ex.: `Premium`, `Standard`, `VIP`). | Filtro |
| `canal` | texto | Canal (`phone`, `digital_voice`). | Filtro |
| `inicio_ts` | datetime ISO | Início do atendimento. | Tendências |
| `fim_ts` | datetime ISO | Fim do atendimento. | Duração |
| `data` | date | Data (yyyy-mm-dd). | Eixo de tempo |
| `dataKey` | inteiro | Chave para `DimData` (yyyymmdd). | Relacionamento |
| `hora` | inteiro (0–23) | Hora de início. | Heatmap por hora |
| `dia_semana` | texto | Nome do dia (Segunda…Domingo). | Sazonalidade |
| `tempo_atendimento_seg` | inteiro | **TMA** — duração em segundos. | **Métrica #3** |
| `qtd_turnos` | inteiro | Total de turnos da conversa. | Complexidade |
| `qtd_interrupcoes` | inteiro | Barge-ins (cliente interrompeu a IA). | Cenário de experiência |
| `latencia_media_ms` | inteiro | **TMR** médio da IA na conversa (ms). | **Métrica #2** |
| `latencia_p95_ms` | inteiro | Latência P95 da IA (ms). | SLA de latência |
| `desfecho` | enum | `retido_ia`, `transbordo_sem_conhecimento`, `transbordo_nao_compreensao`, `transbordo_pedido_atendente`, `transbordo_erro`, `retorno_menu_ura`, `abandono`. | Funil / segmentação |
| `retido_pela_ia` | 0/1 | IA **não** transbordou para fila humana. | **Métrica #1 (Retenção bruta)** |
| `transferido_humano` | 0/1 | Houve transbordo para atendente. | Taxa de transbordo |
| `motivo_transbordo` | enum/vazio | `nao_compreensao`, `sem_conhecimento`, `pedido_atendente`, `erro` ou vazio. | **Métrica #5** |
| `fila_transbordo` | texto | Fila destino (ex.: `atendimento_principal`, `suporte_especializado`). | Detalhe |
| `retornou_menu_ura` | 0/1 | Cliente voltou ao menu URA. | **Métrica #6** |
| `gatilho_retorno_ura` | enum/vazio | `digitou_0` ou `fala_voltar`. | Detalhe #6 |
| `pediu_atendente` | 0/1 | Cliente pediu falar com atendente. | **Métrica #7** |
| `teve_erro` | 0/1 | Houve erro/instabilidade. | **Métrica #8** |
| `tipo_erro` | enum/vazio | `timeout_asr`, `falha_tts`, `erro_integracao`, `instabilidade`. | Página Erros |
| `codigo_erro` | texto/vazio | Código (ex.: `E503`). | Página Erros |
| `intencao_primaria` | enum | Assunto principal (ex.: `resgate_porquinho`). | **Métrica #4** |
| `intencao_rotulo` | texto | Rótulo amigável da intenção. | Rótulos de visual |
| `categoria_intencao` | texto | Categoria (`Investimentos`). | Drill |
| `subcategoria_intencao` | texto | Subcategoria (ex.: `Meu Porquinho`). | Drill |
| `kb_hit` | 0/1 | A base de conhecimento respondeu. | Cobertura |
| `kb_artigos` | texto | Id(s) de artigo(s) da KB usados. | Detalhe |
| `nota_csat` | inteiro/vazio | Nota CSAT (1–5) ou vazio se não respondeu. | **Métrica #9** |
| `respondeu_csat` | 0/1 | Respondeu a pesquisa. | Taxa de resposta |
| `sentimento_geral` | enum | `positivo`, `neutro`, `negativo`. | Donut de sentimento |
| `sentimento_score` | decimal (−1..1) | Score de sentimento geral. | Correlação |
| `sentimento_inicio` | decimal | Sentimento no início. | Evolução |
| `sentimento_fim` | decimal | Sentimento no fim. | Evolução |
| `flag_precisao` | 0/1 | Resposta correta (eval). | Qualidade da IA |
| `flag_compreensao` | 0/1 | Intenção compreendida (eval). | Qualidade |
| `flag_alucinacao` | 0/1 | Resposta alucinada (eval). | Qualidade |
| `flag_cobertura` | 0/1 | Coberto pela KB. | Qualidade |
| `usou_desambiguacao` | 0/1 | Houve desambiguação. | Qualidade |
| `score_aderencia_persona` | decimal (0..1) | Aderência a persona/voz/experiência. | Qualidade |
| `transcricao_disponivel` | 0/1 | Transcrição existe. | Detalhe |
| `url_gravacao` | URL | Link do áudio. **Data category = Web URL** no Power BI. | Link no Detalhe |

## 2. `turns.csv` → `FatoTurno`

| Coluna | Tipo | Descrição | Uso |
|---|---|---|---|
| `turnoId` | texto | Chave do turno. | Chave |
| `conversationId` | GUID | FK para `FatoConversa`. | Relacionamento |
| `indice` | inteiro | Ordem do turno (0..n). | Eixo da transcrição/sentimento |
| `ts` | datetime ISO | Timestamp do turno. | Tempo |
| `autor` | enum | `ia`, `cliente`, `system`. | Filtro transcrição / **TMR (só `ia`)** |
| `texto` | texto | Fala transcrita. | **Matriz da transcrição** |
| `intencao` | enum/vazio | Intenção detectada (turnos do cliente). | Análise |
| `confianca_nlu` | decimal/vazio | Confiança do NLU (0..1). | Diagnóstico de não-compreensão |
| `latencia_resposta_ms` | inteiro/vazio | **TMR** — latência da resposta da IA (só turnos `ia`). | **Métrica #2** |
| `sentimento` | enum | Sentimento do turno. | Formatação condicional |
| `sentimento_score` | decimal (−1..1) | Score do turno. | **Linha do tempo de sentimento** |
| `interrupcao` | 0/1 | Turno gerou/foi interrupção (barge-in). | Cenário de experiência |
| `kb_artigo_id` | texto/vazio | Artigo da KB usado na resposta. | Detalhe |
| `fallback` | 0/1 | IA não entendeu / caiu em fallback. | Diagnóstico #5 |

## 3. `events.csv` → `FatoEvento`

| Coluna | Tipo | Descrição | Uso |
|---|---|---|---|
| `eventId` | texto | Chave do evento. | Chave |
| `conversationId` | GUID | FK para `FatoConversa`. | Relacionamento |
| `ts` | datetime ISO | Timestamp do evento. | Funil / tempo |
| `tipo_evento` | enum | `session_start`, `nlu_intent`, `kb_query`, `error`, `ura_return`, `agent_requested`, `transfer_completed`, `session_end`, `csat_response`. | Funil |
| `subtipo` | texto | Detalhe do evento (intenção, motivo, gatilho, nota...). | Drill |
| `latencia_ms` | inteiro/vazio | Latência associada (ex.: `kb_query`, `nlu_intent`). | Performance |
| `codigo_erro` | texto/vazio | Código do erro (só `error`). | **Página Erros (#8)** |
| `mensagem_erro` | texto/vazio | Mensagem do erro. | Página Erros |
| `severidade` | enum | `info`, `warning`, `error`. | Página Erros |

## 4. `csat.csv` → `FatoCsat`

| Coluna | Tipo | Descrição | Uso |
|---|---|---|---|
| `csatId` | texto | Chave da resposta. | Chave |
| `conversationId` | GUID | FK para `FatoConversa`. | Relacionamento |
| `id_cliente_anon` | texto | Cliente anonimizado. | Segmentação |
| `nota_csat` | inteiro (1–5) | Nota da pesquisa. | **Métrica #9** |
| `comentario_csat` | texto | Comentário livre. | Análise qualitativa |
| `ts` | datetime ISO | Momento da resposta. | Tendência |
| `canal_pesquisa` | enum | `ura_pos_call`, `sms`, `push_app`. | Segmentação |

## 5. `dim_data.csv` → `DimData`

| Coluna | Tipo | Descrição |
|---|---|---|
| `dataKey` | inteiro | Chave (yyyymmdd). Relaciona com `Fato*[dataKey]`. |
| `data` | date | Data. |
| `ano` / `mes` / `dia` | inteiro | Componentes. |
| `nome_mes` | texto | Jan…Dez. |
| `dia_semana` | inteiro (1–7) | 1=Segunda. |
| `nome_dia_semana` | texto | Segunda…Domingo. |
| `semana_ano` | inteiro | Semana do ano. |
| `fim_de_semana` | 0/1 | 1 = sábado/domingo. |

> **Dica Power BI:** marque `DimData` como **tabela de datas** (Mark as date table) usando `data`.

---

## Como carregar no Power BI (teste rápido)

1. **Obter Dados → Texto/CSV** e importe os 5 CSVs de `output/` (encoding UTF-8 / 65001).
2. Em `conversations`, defina `url_gravacao` com **Categoria de Dados = URL da Web**.
3. Crie relacionamentos por `conversationId` e `dataKey`.
4. **Marque `dim_data` como tabela de datas** (coluna `data`).
5. Cole as medidas DAX (ver [`../powerbi-prompts.md`](../powerbi-prompts.md), Prompt 2).
6. Configure o _drill-through_ da página **Detalhe da Conversa** por `conversationId`.

## Regenerar a amostra

```bash
cd docs/sample-data
python gerar_dados_sinteticos.py --conversas 600 --dias 30 --seed 42
```

Parâmetros: `--conversas` (nº de atendimentos), `--dias` (janela de datas), `--seed` (reprodutível).
