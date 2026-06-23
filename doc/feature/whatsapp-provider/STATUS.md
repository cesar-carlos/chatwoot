# Status — WhatsApp providers no fork

Fonte curta de verdade para o estado da pasta `doc/feature/whatsapp-provider/` e do código relacionado.

## Resumo executivo

| Provider | Chave | Documentação | Código | Situação |
|----------|-------|--------------|--------|----------|
| Evolution API | `evolution` | ✅ | ✅ | Provider alternativo ativo no fork |
| Evolution Go | `evolution_go` | ✅ | ❌ | Planejamento pronto, implementação não iniciada |
| Z-API | `zapi` | ✅ plano + Postman | ❌ | Documentação em `z-api/`; código após piloto estável |
| NotificaMe | — | ⚠️ referência cruzada | ❌ | Mantido em pasta própria |

## O que existe hoje em código

### Backend

| Área | Local | Estado |
|------|-------|--------|
| Whitelist de provider | `app/models/channel/whatsapp.rb` | ✅ `evolution` |
| Registry de providers | `custom/lib/messaging_provider/registry.rb` | ✅ |
| Registro do provider | `custom/config/initializers/messaging_provider_registry.rb` | ✅ só `evolution` |
| Overlay do model | `custom/app/models/custom/channel/whatsapp.rb` | ✅ |
| Webhook receiver | `custom/app/controllers/webhooks/evolution_controller.rb` | ✅ |
| Dispatch/normalização de eventos | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | ✅ |
| Bypass janela 24h | `custom/app/services/custom/conversations/message_window_service.rb` | ✅ |
| Serviços Evolution | `custom/app/services/custom/whatsapp/evolution/` | ✅ |

### Frontend

| Área | Local | Estado |
|------|-------|--------|
| Card / wizard Evolution | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Evolution.vue` | ✅ |
| Modal QR | `custom/app/javascript/dashboard/components/evolution/EvolutionQrScanModal.vue` | ✅ |
| Settings / health | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/` | ✅ |
| Card Evolution Go | — | ❌ |

### Testes e fixtures

| Área | Local | Estado |
|------|-------|--------|
| Specs Ruby | `spec/custom/` | ✅ para `evolution` |
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
| [evolution-go/](./evolution-go/README.md) | Documentação de planejamento do próximo provider |

## Lacunas reais restantes

| Tema | Estado |
|------|--------|
| E2E final do fluxo Evolution em ambiente estável/CI | ⚠️ ainda operacional |
| `evolution_go` em `PROVIDERS` | ❌ |
| `evolution_go` no registry, webhook e settings | ❌ |
| Estratégia comum de capabilities para gateways além de `evolution` | ⚠️ parcialmente implícita |
| Providers Z-API / NotificaMe no mesmo padrão | ❌ |

## Ordem de trabalho recomendada

1. Fechar a validação operacional de `evolution` com o fluxo já existente.
2. Só depois iniciar `evolution_go`, reaproveitando registry, prepend e padrão de normalizer.
3. Deixar Z-API e NotificaMe para quando o contrato multi-provider estiver estável.

## Manutenção

- Quando o código mudar, atualize este arquivo primeiro.
- Evite repetir aqui detalhes longos de API ou UX; eles pertencem ao README do provider.
- Se um documento virar histórico e deixar de orientar implementação ou operação, consolide no documento pai em vez de abrir mais uma página paralela.
