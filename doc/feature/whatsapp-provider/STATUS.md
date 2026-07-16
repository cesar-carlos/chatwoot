# Status — WhatsApp providers no fork

Fonte curta de verdade para o estado da pasta `doc/feature/whatsapp-provider/` e do código relacionado.

## Resumo executivo

| Provider | Chave | Documentação | Código | Situação |
|----------|-------|--------------|--------|----------|
| Evolution API | `evolution` | ✅ | ✅ | Provider alternativo ativo no fork |
| Evolution Go | `evolution_go` | ✅ | ✅ | Provider alternativo ativo no fork |
| Z-API | `zapi` | ✅ plano + Postman | ❌ | Documentação em `z-api/`; código após piloto estável |
| NotificaMe | — | ⚠️ referência cruzada | ❌ | Mantido em pasta própria |

## O que existe hoje em código

### Backend

| Área | Local | Estado |
|------|-------|--------|
| Whitelist de provider | `app/models/channel/whatsapp.rb` | ✅ `evolution`, `evolution_go` |
| Registry de providers | `custom/lib/messaging_provider/registry.rb` | ✅ |
| Registro do provider | `custom/config/initializers/messaging_provider_registry.rb` | ✅ `evolution`, `evolution_go` |
| Overlay do model | `custom/app/models/custom/channel/whatsapp.rb` | ✅ |
| Webhook receiver | `custom/app/controllers/webhooks/evolution_controller.rb`, `evolution_go_controller.rb` | ✅ |
| Dispatch/normalização de eventos | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | ✅ |
| Bypass janela 24h | `custom/app/services/custom/conversations/message_window_service.rb` | ✅ |
| Serviços Evolution | `custom/app/services/custom/whatsapp/evolution/` | ✅ |
| Serviços Evolution Go | `custom/app/services/custom/whatsapp/evolution_go/` | ✅ |

### Frontend

| Área | Local | Estado |
|------|-------|--------|
| Card / wizard Evolution | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Evolution.vue` | ✅ |
| Card / wizard Evolution Go | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/EvolutionGo.vue` | ✅ |
| Modal QR | `custom/app/javascript/dashboard/components/evolution/EvolutionQrScanModal.vue`, `evolution_go/EvolutionGoQrScanModal.vue` | ✅ |
| Settings / health | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/` | ✅ |
| Pseudo-forward (mensagem) | `custom/.../useMessageForward.js` + modal; docs [../message-forward/](../message-forward/) | ✅ |

### Testes e fixtures

| Área | Local | Estado |
|------|-------|--------|
| Specs Ruby | `spec/custom/` | ✅ para `evolution` e `evolution_go` |
| Fixtures Evolution | `spec/fixtures/evolution/` | ✅ |
| Fixtures Evolution Go | `spec/fixtures/evolution_go/` | ⚠️ templates, ainda sem capturas reais |
| Validação operacional | `lib/tasks/evolution_validate.rake` | ✅ suporte ao checklist |

## Estado da documentação

### Base do fork

| Documento | Papel atual |
|-----------|-------------|
| [README.md](./README.md) | Entrada principal e mapa da pasta |
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Contrato atual do Chatwoot + overlay do fork |
| [gaps-and-blockers.md](./gaps-and-blockers.md) | Lacunas ainda abertas |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Guia para decidir antes de implementar |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Plano estrutural compartilhado |

### Providers

| Pasta | Papel atual |
|-------|-------------|
| [evolution-api/](./evolution-api/README.md) | Documentação operacional do provider já implementado |
| [evolution-go/](./evolution-go/README.md) | Documentação operacional do provider Go implementado |

## Lacunas reais restantes

| Tema | Estado |
|------|--------|
| E2E final do fluxo Evolution em ambiente estável/CI | ⚠️ ainda operacional |
| Estratégia comum de capabilities para gateways além de `evolution` | ⚠️ parcialmente implícita |
| Providers Z-API / NotificaMe no mesmo padrão | ❌ |

## Ordem de trabalho recomendada

1. Fechar a validação operacional de `evolution` e `evolution_go` com os fluxos já existentes.
2. Deixar Z-API e NotificaMe para quando o contrato multi-provider estiver estável.

## Manutenção

- Quando o código mudar, atualize este arquivo primeiro.
- Evite repetir aqui detalhes longos de API ou UX; eles pertencem ao README do provider.
- Se um documento virar histórico e deixar de orientar implementação ou operação, consolide no documento pai em vez de abrir mais uma página paralela.
