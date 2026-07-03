# TalkSense — Power BI Project (PBIP)

Projeto Power BI Desktop no formato **PBIP + TMDL** (Power BI Project), versionável em Git, contendo o modelo semântico com as **9 métricas core** do TalkSense e um relatório inicial (Overview).

## Estrutura

```
powerbi/
├── TalkSense.pbip                  # Arquivo raiz — abra este no Power BI Desktop
├── TalkSense.Report/                # Definição do relatório (PBIR)
│   └── definition/pages/            # Página "Overview" populada com as 9 métricas core (cards + gráfico de intents)
└── TalkSense.SemanticModel/         # Modelo semântico (TMDL)
    └── definition/
        ├── model.tmdl                # Metadados do modelo, cultura, referências às tabelas
        ├── relationships.tmdl        # Relacionamentos entre tabelas
        └── tables/                   # Um arquivo .tmdl por tabela (colunas, medidas, partição M)
```

## Modelo de dados

| Tabela | Papel | Origem |
|--------|-------|--------|
| `Conversations` | Dimensão/grão de conversa (1 linha por atendimento) | `docs/sample-data/output/conversations.csv` |
| `Turns` | Fato — 1 linha por turno de conversa | `docs/sample-data/output/turns.csv` |
| `Events` | Fato — 1 linha por evento de telemetria | `docs/sample-data/output/events.csv` |
| `Csat` | Fato — 1 linha por resposta de pesquisa CSAT | `docs/sample-data/output/csat.csv` |
| `DimDate` | Dimensão calendário | `docs/sample-data/output/dim_data.csv` |

Relacionamentos: `Conversations (1) → Turns/Events/Csat (*)` via `conversationId`. A tabela `DimDate` está carregada como referência de calendário autônoma (sem relacionamento explícito) — uma coluna calculada `DateKey` + relacionamento para `DimDate` foi removida por causar erro de "cyclic reference" no Power BI Desktop; use os hidden auto date tables do próprio Power BI (Auto Date/Time) para segmentação temporal, ou relacione `DimDate` manualmente pela UI se precisar de uma dimensão de calendário explícita.

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

## Página Overview

A página **Overview** já vem populada com as **9 métricas core** (8 cartões + 1 gráfico "Principais Acionamentos por Intent"), no formato **PBIR gerado pelo próprio Power BI Desktop** (seguro para versionar). **Ao adicionar novos visuais, atenção:** versionar visuais como arquivos PBIR (`visual.json`) **editados à mão** causou um crash reproduzível no Power BI Desktop (`Cannot read properties of undefined (reading 'visualContainers')` em `DesktopExplorationComponent.onExplorationActivated`), mesmo com JSON validado contra o schema oficial. A causa raiz é uma incompatibilidade do parser de PBIR desta build do Desktop com visuals autorados manualmente — não um defeito no modelo. O caminho confiável é adicionar os cards pela interface:

1. Abra `powerbi/TalkSense.pbip` no Power BI Desktop e confirme que a página **Overview** está selecionada.
2. Na faixa **Inserir**, clique em **Visual** → escolha **Cartão** (Card) — repita para cada métrica que quiser adicionar.
3. Com o cartão selecionado, no painel **Dados** (lado direito), localize a tabela e arraste a medida para o campo **Valores** do cartão:

   | Cartão | Tabela | Medida |
   |---|---|---|
   | Retenção IA | `Conversations` | `Retencao IA (%)` |
   | TMR | `Turns` | `TMR (segundos)` |
   | CSAT | `Csat` | `CSAT Medio` |
   | Erros do Sistema | `Events` | `Taxa de Erro (%)` |

4. (Opcional) No painel **Formatar visual**, ajuste o rótulo de categoria (**Categoria label** → texto customizado) para exibir o nome amigável da métrica (ex.: "Retenção IA (%)") acima do valor.
5. Redimensione/posicione os 4 cartões lado a lado (arraste pelas alças do visual) e salve (**Ctrl+S**).
6. Faça commit do PBIP atualizado — o Power BI Desktop vai reescrever `TalkSense.Report/definition/pages/overview/` com o formato PBIR nativo dele, que é seguro para versionar (foi o próprio Desktop que gerou, não um autor manual).

Após salvar pela UI uma vez, o arquivo `visual.json` gerado pelo Desktop pode servir de referência/modelo caso você queira replicar o padrão para novas páginas — mas continue preferindo a UI para criar visuals novos, dado o bug de renderização observado.

### Criando páginas de relatório adicionais

Para adicionar novas páginas (ex.: "Turns", "Eventos", "CSAT" detalhados):

1. Clique no **+** ao lado das abas de página, na parte inferior do canvas.
2. Renomeie a página (duplo clique na aba) seguindo o padrão em minúsculas usado internamente (ex. `turns-detail`) — o nome de exibição pode ser diferente e mais amigável (ex. "Turnos").
3. Adicione visuals normalmente pela UI (gráficos de coluna/linha para `Acionamentos por Intent`/`Rank Intent`, tabela para detalhamento de `Turns`, etc.).
4. Salve e comite — assim como a página Overview, o Power BI Desktop gerencia a estrutura PBIR automaticamente.

## Migrando para produção (Direct Lake / DirectQuery no Eventhouse)

Este PBIP usa **Import Mode** local (via CSV) para permitir abrir e validar o modelo sem depender de infraestrutura Fabric provisionada. Para apontar para o Eventhouse real após o deploy do Plano B:

1. Siga [`../infra/docs/fabric-configuration.md`](../infra/docs/fabric-configuration.md) para provisionar o Eventhouse e habilitar OneLake Availability.
2. No Power BI Desktop, **Transformar Dados → Configurações de Fonte de Dados**, ou recrie as tabelas via **Obter Dados → OneLake data hub** (Direct Lake) ou **Azure Data Explorer (Kusto)** (DirectQuery), apontando para o Eventhouse `VoiceAgentEventhouse` / banco `VoiceAgentDB`.
3. Mantenha os nomes de tabela/coluna idênticos (`Conversations`, `Turns`, `Events`, `Csat`, `DimDate`) para que as medidas DAX continuem funcionando sem alterações.

Detalhes completos: [`../infra/docs/powerbi-configuration.md`](../infra/docs/powerbi-configuration.md).