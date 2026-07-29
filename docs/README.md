# Documentação — Analytics do Agente de Voz (Investimentos)

Esta pasta contém o plano de telemetria/analytics do agente de voz e os artefatos de apoio para
construir o **dashboard no Power BI** (visão geral + drill-downs + detalhe da conversa).

## Índice

| Documento | Descrição |
|---|---|
| [`plano-telemetria-analytics.md`](./plano-telemetria-analytics.md) | **Plano principal**: arquitetura, esquema de telemetria, definição/fórmula das 9 métricas, modelo de dados Cosmos DB, star schema e páginas do dashboard com drill-through. |
| [`adr/README.md`](./adr/README.md) | **Índice de ADRs**: decisões propostas para Foundry, voz, knowledge mining, Event Hubs/Fabric, ontologia, arquitetura ponta a ponta e segurança. |
| [`adr/implementation-roadmap.md`](./adr/implementation-roadmap.md) | Roadmap faseado com premissas e tarefas de implementação em formato de checklist de issues. |
| [`diagrams/`](./diagrams/) | Diagramas de arquitetura editáveis (**draw.io**) das opções originais de ingestão analítica. |
| [`powerbi-prompts.md`](./powerbi-prompts.md) | Avaliação das **skills de Power BI via código** + **prompts prontos** (modelagem, DAX, layout, validação). |
| [`sample-data/dicionario-de-dados.md`](./sample-data/dicionario-de-dados.md) | **Dicionário de dados** — todas as colunas que o Power BI precisa. |
| [`sample-data/gerar_dados_sinteticos_talksense.py`](./sample-data/gerar_dados_sinteticos_talksense.py) | Gerador de **dados sintéticos** (somente teste; sem dados reais). |
| [`sample-data/output/`](./sample-data/output/) | Amostras geradas: `conversations.csv`, `turns.csv`, `events.csv`, `csat.csv`, `dim_data.csv`, `conversation_sample.json`. |

## As 9 métricas do escopo (resumo)

1. Retenção bruta da IA · 2. TMR (latência) · 3. TMA · 4. Principais acionamentos ·
5. Transbordo por não-compreensão/falta de conhecimento · 6. Retorno ao menu URA ·
7. Pedido de atendente · 8. Erros · 9. Pesquisa CSAT.

## Começar rápido

```bash
# 1) Gerar/atualizar a amostra
cd sample-data
python gerar_dados_sinteticos.py --conversas 600 --dias 30 --seed 42

# 2) No Power BI Desktop: importar os CSV de sample-data/output/,
#    criar relacionamentos por conversationId/dataKey e colar as medidas de powerbi-prompts.md
```
