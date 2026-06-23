# Tasks — Z-API (`zapi`)

Backlog técnico ordenado. Status geral: [status.md](./status.md)

---

## Documentação

- [x] Inventário Postman MCP
- [x] `documentation-links.md`, `api-reference.md`, `webhook-events.md`
- [x] `decisions.md`, `spec-design.md`, `implementation-plan.md`
- [x] `feature-mapping.md`, `validation-checklist.md`, `frontend-wizard-spec.md`
- [x] Revisão cruzada Postman + doc oficial + código Evolution — [documentation-review.md](./documentation-review.md)
- [ ] Capturar fixtures E2E reais (`spec/fixtures/zapi/`)
- [ ] Confirmar path `update-every-webhooks` no E2E
- [ ] `troubleshooting.md` (após piloto)

---

## Fase 0 — Infra

- [ ] `PROVIDERS` + `zapi` em `channel/whatsapp.rb`
- [ ] Registry `zapi` em `messaging_provider_registry.rb`
- [ ] Capability `unlimited_session`
- [ ] Rota `POST /webhooks/zapi/:instance_id`
- [ ] Stub `ZapiController`
- [ ] Migration índice `instance_id` unique

---

## Fase 1 — MVP

- [ ] `Zapi::ApiClient`
- [ ] `Zapi::ConnectionService` (webhooks + status + qr)
- [ ] `ZapiService` send texto
- [ ] `ZapiNormalizer` (Received + MessageStatus + Disconnected)
- [ ] prepend `WhatsappEventsJob`
- [ ] `ZapiWhatsapp.vue` wizard (2 steps)
- [ ] Settings card conexão
- [ ] Specs normalizer + ApiClient

---

## Fase 2

- [ ] Mídia send + inbound download
- [ ] `read-message` + status READ outbound
- [ ] `GET /contacts` import
- [ ] Partners API no wizard
- [ ] `ConnectedCallback` handling

---

## Fase 3+

- [ ] Reply threading (`messageId` quote)
- [ ] Interativos (botões/listas) — avaliar necessidade
- [ ] Contact card outbound
