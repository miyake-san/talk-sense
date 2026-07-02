# TalkSense — Power BI Project (PBIP)

Projeto Power BI Desktop no formato **PBIP + TMDL** (Power BI Project), versionável em Git, contendo o modelo semântico com as **9 métricas core** do TalkSense e um relatório inicial (Overview).

## Estrutura

```
powerbi/
├── TalkSense.pbip                  # Arquivo raiz — abra este no Power BI Desktop
├── TalkSense.Report/                # Definição do relatório (PBIR)
│   └── definition/pages/overview/   # Página "Overview" com 4 cards KPI
└── TalkSense.SemanticModel/         # Modelo semântico (TMDL)
    └── definition/model.tmdl        # Tabelas, colunas, relacionamentos e medidas DAX
```

## Modelo de dados

| Tabela | Papel | Origem |
|--------|-------|--------|
| `Conversations` | Dimensão/grão de conversa (1 linha por atendimento) | `docs/sample-data/output/conversations.csv` |
| `Turns` | Fato — 1 linha por turno de conversa | `docs/sample-data/output/turns.csv` |
| `Events` | Fato — 1 linha por evento de telemetria | `docs/sample-data/output/events.csv` |
| `Csat` | Fato — 1 linha por resposta de pesquisa CSAT | `docs/sample-data/output/csat.csv` |
| `DimDate` | Dimensão calendário | `docs/sample-data/output/dim_data.csv` |

Relacionamentos: `Conversations (1) → Turns/Events/Csat (*)` via `conversationId`, e `DimDate (1) → Conversations (*)` via uma coluna calculada `DateKey` (derivada de `timestamp`).

## As 9 métricas (medidas DAX)

| # | Métrica | Medida DAX | Tabela |
|---|---------|-----------|--------|
| 1 | Retenção Bruta da IA | `Retencao IA (%)` | Conversations |
| 2 | TMR (Tempo Médio de Resposta) | `TMR (segundos)` | Turns |
| 3 | TMA (Tempo Máximo de Atendimento) | `TMA (segundos)` | Turns |
| 4 | Principais Acionamentos | `Acionamentos por Intent` / `Rank Intent` | Turns |
| 5 | Transbordo por Não-Compreensão | `Transbordo Nao Compreensao (%)` | Events |
| 6 | Retorno ao Menu URA | `Retorno URA (%)` | Events |
| 7 | Pedido de Atendente | `Pedido Atendente (%)` | Events |
| 8 | Erros do Sistema | `Taxa de Erro (%)` | Events |
| 9 | Pesquisa CSAT | `CSAT Medio` / `NPS` | Csat |

Todas as medidas e fórmulas DAX completas estão documentadas em [`../infra/docs/powerbi-configuration.md`](../infra/docs/powerbi-configuration.md).

## Como abrir

1. Abra o Power BI Desktop (versão atual — suporte a projetos PBIP habilitado por padrão desde 2024).
2. **Arquivo → Abrir → Procurar** e selecione `powerbi/TalkSense.pbip`.
3. Na primeira abertura, o Power BI vai pedir para localizar a fonte de dados: os CSVs de amostra em `docs/sample-data/output/`.
   - Vá em **Transformar Dados** → selecione a query de cada tabela → edite o passo **Source** e substitua `<ABSOLUTE_PATH_TO_REPO>` pelo caminho absoluto local do repositório (ex.: `C:\Users\voce\talk-sense`).
   - Gere os CSVs antes, se necessário: `python docs/sample-data/gerar_dados_sinteticos_talksense.py --conversas 1000 --dias 30`.
4. Clique em **Atualizar** para carregar os dados.

## Migrando para produção (Direct Lake / DirectQuery no Eventhouse)

Este PBIP usa **Import Mode** local (via CSV) para permitir abrir e validar o modelo sem depender de infraestrutura Fabric provisionada. Para apontar para o Eventhouse real após o deploy do Plano B:

1. Siga [`../infra/docs/fabric-configuration.md`](../infra/docs/fabric-configuration.md) para provisionar o Eventhouse e habilitar OneLake Availability.
2. No Power BI Desktop, **Transformar Dados → Configurações de Fonte de Dados**, ou recrie as tabelas via **Obter Dados → OneLake data hub** (Direct Lake) ou **Azure Data Explorer (Kusto)** (DirectQuery), apontando para o Eventhouse `VoiceAgentEventhouse` / banco `VoiceAgentDB`.
3. Mantenha os nomes de tabela/coluna idênticos (`Conversations`, `Turns`, `Events`, `Csat`, `DimDate`) para que as medidas DAX continuem funcionando sem alterações.

Detalhes completos: [`../infra/docs/powerbi-configuration.md`](../infra/docs/powerbi-configuration.md).