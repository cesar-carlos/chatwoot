# WhatsApp Provider — visão geral

Documentação do fork para providers WhatsApp alternativos em `Channel::Whatsapp`.

Hoje o repositório tem um provider alternativo **implementado** e outros **apenas documentados**:

| Provider | Chave | Estado |
|----------|-------|--------|
| Evolution API (Node/Baileys) | `evolution` | ✅ código em `custom/` + specs |
| Evolution Go (whatsmeow) | `evolution_go` | ✅ código em `custom/` + specs |
| Z-API | `zapi` | ✅ [z-api/](./z-api/) |
| NotificaMe / genéricos | — | 📄 comparação apenas |

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

O fork já estendeu o fluxo padrão do Chatwoot para `evolution` sem alterar o caminho cloud:

- `app/models/channel/whatsapp.rb`: `PROVIDERS` inclui `evolution`
- `custom/lib/messaging_provider/registry.rb`: registry de providers alternativos
- `custom/app/models/custom/channel/whatsapp.rb`: dispatch por registry + sync/mascara de config
- `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb`: roteamento e normalização de webhooks Evolution
- `custom/app/services/custom/conversations/message_window_service.rb`: bypass da janela de 24h para `evolution`
- `custom/app/services/custom/whatsapp/evolution/`: adapter REST, normalizer, provisionamento, sync e import
- `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Evolution.vue`: wizard do provider

Resumo importante:

- Só `evolution` está ligado ao código hoje.
- `evolution_go` ainda **não** está em `PROVIDERS`, no registry ou nas rotas.
- Voz continua sendo assunto separado em `doc/feature/whatsapp-voice/`.

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
| [evolution-api/](./evolution-api/README.md) | Provider em produção no fork: contratos, operação, troubleshooting |
| [evolution-go/](./evolution-go/README.md) | Provider planejado: decisões, contratos e plano antes do código |

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
