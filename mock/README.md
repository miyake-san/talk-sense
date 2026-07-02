# mock/ — Simuladores para Prova de Conceito (POC)

Esta pasta contém ferramentas que **simulam componentes reais** da arquitetura do TalkSense, usadas apenas em ambientes de teste/POC — nunca em produção.

## Conteúdo

| Arquivo | O que simula | Onde executar |
|---------|---------------|---------------|
| [`talksense_eventhub_simulator.ipynb`](talksense_eventhub_simulator.ipynb) | O **Voice Agent + Azure Event Hubs** reais, enviando eventos JSON continuamente para o Fabric Eventstream (ou diretamente para a Eventhouse) | Notebook do **Microsoft Fabric** (importar no workspace) |

## Por que isso existe

Validado durante a revisão da infraestrutura: os scripts de deploy (`infra/deploy-planb.ps1`, `infra/bicep/deploy.ps1`, `infra/terraform/main.tf`) **provisionam apenas a infraestrutura** (Event Hub, Eventstream, Eventhouse) — eles **não geram nem enviam** os datasets de amostra em `docs/sample-data/output/`. Esse notebook preenche essa lacuna para cenários de POC, gerando tráfego sintético de forma contínua e realista (mesmo schema JSON de produção) sem precisar de um Event Hub real.

## Uso rápido

1. Provisione o Eventstream/Eventhouse: ver [`../infra/docs/fabric-configuration.md`](../infra/docs/fabric-configuration.md).
2. Importe `talksense_eventhub_simulator.ipynb` em um workspace do Fabric.
3. Configure `EVENTSTREAM_CONNECTION_STRING` (endpoint "Custom App" do Eventstream) na célula de configuração.
4. Execute todas as células — o simulador roda em loop até `MAX_RUNTIME_MINUTES` ou até ser interrompido manualmente.
5. Valide a chegada dos dados com uma consulta KQL na Eventhouse (exemplo incluso no notebook).