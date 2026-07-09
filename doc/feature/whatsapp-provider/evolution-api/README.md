# Evolution API — provider `evolution`

Landing page do provider WhatsApp alternativo **já implementado** no fork.

## Estado atual

| Item | Estado |
|------|--------|
| Chave do provider | `evolution` |
| `PROVIDERS` no model | ✅ |
| Código em `custom/` | ✅ |
| Wizard / settings | ✅ |
| Specs Ruby | ✅ |
| Validação operacional final | ⚠️ ainda depende de ambiente real consistente |

Status geral do domínio: [../STATUS.md](../STATUS.md)

## Onde o código vive

| Área | Local |
|------|-------|
| Registry / dispatch | `custom/lib/messaging_provider/registry.rb` + `custom/app/models/custom/channel/whatsapp.rb` |
| Webhook receiver | `custom/app/controllers/webhooks/evolution_controller.rb` |
| Job / normalização | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` |
| Serviços REST e operação | `custom/app/services/custom/whatsapp/evolution/` |
| Provider service | `custom/app/services/custom/whatsapp/providers/evolution_service.rb` |
| Wizard / QR / settings | `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/` |
| Fixtures / specs | `spec/fixtures/evolution/` + `spec/custom/` |

## Use esta pasta assim

| Se você precisa... | Leia primeiro |
|--------------------|---------------|
| Entender o escopo implementado | [implementation-plan.md](./implementation-plan.md) |
| Ver decisões fechadas | [decisions.md](./decisions.md) |
| Conferir contratos REST | [api-reference.md](./api-reference.md) |
| Conferir payloads de webhook | [webhook-events.md](./webhook-events.md) |
| Mapear `provider_config` | [provider-config-mapping.md](./provider-config-mapping.md) |
| Entender regras do inbox e defaults | [inbox-business-rules.md](./inbox-business-rules.md) |
| Operar, migrar ou depurar | [troubleshooting.md](./troubleshooting.md) · [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) |
| Validar contra instância real | [validation-checklist.md](./validation-checklist.md) |

## Escopo já coberto pelo fork

- criação de inbox `provider: 'evolution'`
- provisionamento da instância e registro de webhook
- QR / estado de conexão / reconnect
- envio e recebimento de texto
- mídia, sync de status, sync de contatos e import
- bypass da janela de 24h para sessão livre
- settings específicos de Evolution no dashboard
- inbound contacts, reply context, button/list replies
- typing indicator → `POST /chat/sendPresence`

## Pontos que continuam importantes

- Desabilitar a integração legada Evolution → Chatwoot para evitar duplicidade.
- Tratar voz como escopo separado; este provider cobre mensagens.
- Preferir atualizar o documento específico do assunto em vez de repetir contexto neste README.

## Documentos de apoio

| Documento | Papel |
|-----------|-------|
| [documentation-links.md](./documentation-links.md) | Índice das fontes oficiais e compatibilidade de versão |
| [postman-validation.md](./postman-validation.md) | Cruzamento da collection Postman com o fork |
| [spec-design.md](./spec-design.md) | Contratos das classes em `custom/` |
| [business-rules-adaptation.md](./business-rules-adaptation.md) | Adaptação das regras do produto para o fork |
| [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md) | Contexto da integração legada da Evolution |
| [tasks.md](./tasks.md) | Backlog operacional / técnico do provider |

## Relação com a documentação pai

- visão geral dos providers: [../README.md](../README.md)
- arquitetura e extension points do Chatwoot: [../architecture-current-whatsapp.md](../architecture-current-whatsapp.md)
- lacunas ainda abertas: [../gaps-and-blockers.md](../gaps-and-blockers.md)
- comparação com Evolution Go: [../evolution-go/README.md](../evolution-go/README.md)
