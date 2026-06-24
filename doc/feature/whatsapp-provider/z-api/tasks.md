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

- [ ] `Zapi::ApiError` (exceção tipada — base para ApiClient)
- [ ] `Zapi::ApiClient`
- [ ] `Zapi::ConnectionService` (webhooks + status + qr + sync_phone_number)
- [ ] `Zapi::ConnectionEvents` (side-effects Connected/Disconnected: DB + ActionCable)
- [ ] `ZapiConnectionChannel` (ActionCable `zapi:connection:{inbox_id}`)
- [ ] `ZapiService` send texto
- [ ] `ZapiNormalizer` (Received + MessageStatus + Delivery + Connected + Disconnected — só parse)
- [ ] prepend `WhatsappEventsJob` — `dispatch_zapi_event` com router por `type`
- [ ] `ZapiWhatsapp.vue` wizard (2 steps)
- [ ] Settings card conexão
- [ ] Specs normalizer + ApiClient

---

## Fase 2

- [ ] Mídia send + inbound download
- [ ] `read-message` + status READ outbound
- [ ] Reply/quote — `messageId` no `send-text`
- [ ] `GET /contacts` import
- [ ] Partners API no wizard (Step 1 alternativo)

---

## Fase 3+

- [ ] Reply threading (`messageId` quote)
- [ ] Interativos (botões/listas) — avaliar necessidade
- [ ] Contact card outbound
