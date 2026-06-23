# Z-API — provider `zapi`

Landing page do provider WhatsApp **SaaS** Z-API no fork.

## Estado atual

| Item | Estado |
|------|--------|
| Chave planejada | `zapi` |
| Documentação de contrato e plano | 🚧 em construção |
| Código em `custom/` | ❌ |
| `PROVIDERS`, registry e webhook | ❌ |
| Validação E2E com instância real | ❌ |

Status geral do domínio: [../STATUS.md](../STATUS.md)

## O que é Z-API

SaaS REST gerenciado em `https://api.z-api.io`. Cada inbox usa uma **instância** (`instance_id` + `instance_token`) com webhooks HTTPS separados por tipo de evento.

Diferente de Evolution (self-host), não há servidor do operador — apenas credenciais Z-API e URLs de callback.

## Fontes oficiais

| Fonte | URL |
|-------|-----|
| Documentação | https://developer.z-api.io/ |
| Collection Postman (oficial) | https://go.postman.co/collection/1696280-cea57506-b9de-4e61-b4d5-227743bd8151 |
| Collection fork (Cesar Carlos) | https://go.postman.co/collection/9985534-cdcfbd61-4ce9-451d-80a8-fe3c5cd6da6d |
| Workspace público Z-API | Z-API's Public Workspace |

## Decisão principal

`zapi` será um provider **separado** de `evolution` e `evolution_go`.

Motivo: autenticação por path (`/instances/{id}/token/{token}/…`), webhooks por URL dedicada (não event bus único) e modelo SaaS com fila interna de envio.

## O que pode ser reaproveitado do fork

| Reuso | Situação |
|-------|----------|
| `MessagingProvider::Registry` | ✅ já existe |
| prepend em `Channel::Whatsapp` | ✅ padrão Evolution |
| prepend em `WhatsappEventsJob` | ✅ padrão Evolution |
| bypass da janela 24h | ✅ padrão Evolution |
| wizard / QR / settings como UX | ✅ reaproveitável com adaptações |

O que muda: cliente REST, normalizer, auth (`Client-Token`), rotas webhook (multiplex ou 4–7 URLs), `provider_config` e provisionamento via painel Z-API ou API Partners.

## Use esta pasta assim

| Se você precisa... | Leia primeiro |
|--------------------|---------------|
| Ver prontidão e lacunas | [status.md](./status.md) |
| Entender o plano de implementação | [implementation-plan.md](./implementation-plan.md) |
| Ver decisões fechadas | [decisions.md](./decisions.md) |
| Conferir contratos REST | [api-reference.md](./api-reference.md) |
| Conferir payloads de webhook | [webhook-events.md](./webhook-events.md) |
| Mapear `provider_config` | [provider-config-mapping.md](./provider-config-mapping.md) |
| Mapear features Chatwoot ↔ Z-API | [feature-mapping.md](./feature-mapping.md) |
| Contratos das classes `custom/` | [spec-design.md](./spec-design.md) |
| Projetar wizard / settings | [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| Regras de negócio adaptadas | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| Comparar com Evolution | [differences-from-evolution-api.md](./differences-from-evolution-api.md) · [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) |
| Índice Postman → doc oficial | [documentation-links.md](./documentation-links.md) |
| Inventário collection | [postman-validation.md](./postman-validation.md) |
| Validar com instância real | [validation-checklist.md](./validation-checklist.md) |
| Auditoria / revisão completa | [documentation-review.md](./documentation-review.md) |
| Backlog técnico | [tasks.md](./tasks.md) |

## Escopo MVP proposto (Fase 1)

- inbox `provider: 'zapi'` com credenciais manuais ou via API Partners
- QR / status de conexão / disconnect
- registrar webhooks (receive, delivery, status, disconnected)
- envio e recebimento de **texto**
- status `SENT` / `RECEIVED` / `READ`
- ignorar grupos no inbound

## Fora do MVP inicial

- Mobile onboarding (registro sem QR)
- Interativos (botões, listas, PIX)
- Grupos, comunidades, newsletter
- WhatsApp Business (catálogo, etiquetas)
- Chamadas de voz
- Sync de histórico via `Chats`

## Relação com a documentação pai

- visão geral: [../README.md](../README.md)
- arquitetura Chatwoot: [../architecture-current-whatsapp.md](../architecture-current-whatsapp.md)
- lacunas abertas: [../gaps-and-blockers.md](../gaps-and-blockers.md)
- provider Evolution (referência de código): [../evolution-api/README.md](../evolution-api/README.md)
