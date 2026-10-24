# WhatsApp Provider — visão geral

Documentação do fork para providers WhatsApp alternativos em `Channel::Whatsapp`.

Dois providers alternativos estão no código. Z-API e NotificaMe não têm plano local:

| Provider | Chave | Estado |
|----------|-------|--------|
| Evolution API (Node/Baileys) | `evolution` | código em `custom/` + specs |
| Evolution Go (whatsmeow) | `evolution_go` | código em `custom/` + specs |
| Z-API | `zapi` | sem código; baixar a doc oficial na implementação |
| NotificaMe / genéricos | — | comparação apenas |

Status consolidado: [STATUS.md](./STATUS.md)

## Como usar esta pasta

| Se você precisa... | Leia primeiro |
|--------------------|---------------|
| Entender o que já existe no código | [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) |
| Ver o estado real por provider | [STATUS.md](./STATUS.md) |
| Avaliar o que ainda bloqueia um novo provider | [gaps-and-blockers.md](./gaps-and-blockers.md) |
| Implementar um novo provider | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| Seguir o plano estrutural do fork | [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) |
| Comparar gateways | [provider-comparison.md](./provider-comparison.md) |
| Ver paridade funcional | [feature-mapping.md](./feature-mapping.md) |

## Estado atual do código

O fork estende o fluxo padrão do Chatwoot para `evolution` e `evolution_go` sem alterar o caminho cloud. Revisão: out/2026.

- `app/models/channel/whatsapp.rb`: `PROVIDERS` inclui `evolution` e `evolution_go`
- `custom/config/initializers/messaging_provider_registry.rb`: os dois providers registrados
- `custom/app/models/custom/channel/whatsapp.rb`: dispatch por registry, sync e máscara de config
- `custom/app/controllers/webhooks/evolution_controller.rb` e `evolution_go_controller.rb`: receivers dedicados
- `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` e `whatsapp_events_job_evolution_go.rb`: normalização antes do incoming flat
- `custom/lib/messaging_provider/capabilities.rb` + `message_window_service.rb`: sessão livre para os dois gateways
- `custom/app/services/custom/whatsapp/evolution/` e `evolution_go/`: adapters REST, normalizers, provisionamento e sync
- Wizards: `Evolution.vue` e `EvolutionGo.vue`, ligados em `Whatsapp.vue`

Voz continua em `doc/feature/whatsapp-voice/`. Z-API não entra em `PROVIDERS` nem no registry. O plano local foi removido por estar desatualizado; na implementação, partir de [developer.z-api.io](https://developer.z-api.io/).

## Estrutura da documentação

### Base do fork

| Documento | Papel |
|-----------|-------|
| [STATUS.md](./STATUS.md) | Fonte curta de verdade sobre código e próximos passos |
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Contratos e pontos de extensão do Chatwoot |
| [gaps-and-blockers.md](./gaps-and-blockers.md) | Riscos e lacunas ainda abertas |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Escolha da abordagem antes de codar |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Plano estrutural para novos providers |
| [provider-comparison.md](./provider-comparison.md) | Escolha de gateway |
| [feature-mapping.md](./feature-mapping.md) | Mapa de features por capacidade |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Trade-offs da API oficial vs não oficial |

### Providers específicos

| Pasta | Papel |
|-------|-------|
| [evolution-api/](./evolution-api/README.md) | Provider implementado: contratos, operação, troubleshooting |
| [evolution-go/](./evolution-go/README.md) | Provider implementado: contratos, operação e lacunas de E2E |

## Relação com outras áreas

| Área | Documento |
|------|-----------|
| Voz WhatsApp oficial / segundo provider de voz | [../whatsapp-voice/README.md](../whatsapp-voice/README.md) |
| Estratégia de voz não oficial | [../whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Integração NotificaMe | documentação ainda não versionada neste repositório |
| Regras do fork / merge safety | [../../../.cursor/rules/fork-workflow.mdc](../../../.cursor/rules/fork-workflow.mdc) |

## Regra prática de manutenção

- Atualize [STATUS.md](./STATUS.md) quando o código mudar de fase.
- Atualize o `README.md` do provider ao abrir ou fechar uma frente de implementação.
- Prefira ajustar o documento específico do provider em vez de repetir o mesmo contexto aqui.
