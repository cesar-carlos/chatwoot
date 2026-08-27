# Evolution Go — provider `evolution_go`

Landing page do provider Evolution Go (implementado).

## Estado atual

| Item | Estado |
|------|--------|
| Chave planejada | `evolution_go` |
| Documentação de contrato e plano | ✅ |
| Código em `custom/` | ✅ Fases 0–4 + UX/diagnóstico/import/grupos/presence (jul/2026; sync doc 27/ago LID 1:1) |
| `PROVIDERS`, registry e webhook | ✅ |
| Fixtures reais | ⚠️ sintéticas — E2E pendente |

Status geral do domínio: [../STATUS.md](../STATUS.md)

## Decisão principal

`evolution_go` será um provider **separado** de `evolution`.

Motivo: apesar do ecossistema comum, REST, autenticação, eventos e payloads divergem o bastante para não reaproveitar o adapter Node sem acoplamento ruim.

Referência: [differences-from-evolution-api.md](./differences-from-evolution-api.md)

## O que já pode ser reaproveitado do fork

| Reuso | Situação |
|-------|----------|
| `MessagingProvider::Registry` | ✅ já existe |
| prepend em `Channel::Whatsapp` | ✅ já existe para `evolution` |
| prepend em `WhatsappEventsJob` | ✅ padrão já existe |
| bypass da janela 24h | ✅ padrão já existe |
| wizard / QR / settings como estrutura de UX | ✅ reaproveitável do provider Evolution |

O que muda: cliente REST, normalizer, auth, rotas, settings e payloads.

## Use esta pasta assim

| Se você precisa... | Leia primeiro |
|--------------------|---------------|
| Ver prontidão e lacunas | [status.md](./status.md) |
| Entender o plano de implementação | [implementation-plan.md](./implementation-plan.md) |
| Ver diferenças para Evolution API Node | [differences-from-evolution-api.md](./differences-from-evolution-api.md) |
| Conferir decisões fechadas | [decisions.md](./decisions.md) |
| Encaminhar mensagem (pseudo-forward) | [../../message-forward/README.md](../../message-forward/README.md) |
| Mapear contratos REST | [api-reference.md](./api-reference.md) |
| Mapear eventos / normalizer | [webhook-events.md](./webhook-events.md) |
| Modelar `provider_config` | [provider-config-mapping.md](./provider-config-mapping.md) |
| Projetar o frontend | [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| Validar com servidor real | [validation-checklist.md](./validation-checklist.md) |
| Diagnosticar inbound/outbound | [troubleshooting.md](./troubleshooting.md) |
| Diagnosticar contatos sem avatar | [avatar-failures-report.md](./avatar-failures-report.md) |

## Escopo (implementado)

- inbox `provider: 'evolution_go'` em `Channel::Whatsapp`
- connect + QR + webhook via REST
- texto, mídia, location, contact, sticker, input_select→buttons/list
- Meta AI / bots: `richResponseMessage` → texto (`submessages[].messageText`); unwrap `botInvokeMessage`
- READ_RECEIPT, mark-read, advanced settings / proxy
- import contatos, delete/edit inbound (plaintext protocol ✅; encrypted-only skip), sync delete/edit outbound (opt-in; UI Edit no context menu)
- diagnóstico operacional e import histórico via `HISTORY_SYNC`
- typing presence outbound (`TypingListener` → `/message/presence`)
- refresh manual de contatos paced (`evolution_go_refresh_contacts`, stagger 3s)
- grupos WhatsApp como conversa única quando `ignore_groups: false` (opt-in)
- message reactions (chip + context menu) — ADR §33
- 1:1 LID vs PN (persistir addressing `@lid`; inbound LID-only) — ADR §37
- **pseudo-forward** de mensagem no Chatwoot (mesmo inbox) — ADR §34 · docs em [../../message-forward/](../../message-forward/)
- sem provisionar o servidor Go dentro deste repositório

**Pendente:** E2E com servidor real; poll/link outbound; proxy edit em instância existente; forward nativo WhatsApp (API Go); encrypted edit residual ([#92](https://github.com/evolution-foundation/evolution-go/issues/92)) quando Go não entrega `editedMessage`.

## Onde este provider encosta no código atual

| Área | Ponto de extensão |
|------|-------------------|
| Model | `app/models/channel/whatsapp.rb` + `custom/app/models/custom/channel/whatsapp.rb` |
| Registry | `custom/config/initializers/messaging_provider_registry.rb` |
| Job | `custom/app/jobs/custom/webhooks/whatsapp_events_job_evolution_go.rb` |
| Janela 24h | `custom/app/services/custom/conversations/message_window_service.rb` |
| Frontend | `EvolutionGo.vue`, Settings/Health pages, composables `evolution_go/` |

## Documentos de apoio

| Documento | Papel |
|-----------|-------|
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Estratégia de coexistência com `evolution` — **inclui alerta prepend collision** |
| [spec-design.md](./spec-design.md) | Contratos das classes previstas |
| [postman-validation.md](./postman-validation.md) | Cruzamento de OpenAPI e Postman |
| [documentation-links.md](./documentation-links.md) | Links oficiais |
| [tasks.md](./tasks.md) | Backlog da implementação |
| [troubleshooting.md](./troubleshooting.md) | Sintomas, causas e ações (inclui 1:1 LID) |
| [documentation-review.md](./documentation-review.md) | Auditoria / revisão completa |

## Relação com a documentação pai

- visão geral dos providers: [../README.md](../README.md)
- arquitetura atual do Chatwoot: [../architecture-current-whatsapp.md](../architecture-current-whatsapp.md)
- plano estrutural compartilhado: [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md)
- provider já implementado: [../evolution-api/README.md](../evolution-api/README.md)
