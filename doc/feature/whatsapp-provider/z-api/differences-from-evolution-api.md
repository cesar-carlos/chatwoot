# Diferenças — Z-API vs Evolution API (fork)

Referência rápida para não misturar adapters. Provider Evolution já implementado: [../evolution-api/README.md](../evolution-api/README.md).

---

## Resumo

| Aspecto | Evolution API (`evolution`) | Z-API (`zapi`) |
|---------|----------------------------|----------------|
| Hosting | Self-host (operador) | SaaS Z-API |
| Base URL | Configurável por inbox | `https://api.z-api.io` |
| Auth REST | Header `apikey` | Path `instance_id/token` + `Client-Token` |
| Instância | `instance_name` slug | `instance_id` UUID-like |
| Webhook config | 1 URL + event list (`/webhook/set`) | 4–7 URLs ou 1 bulk PUT |
| Webhook payload | `event` + `data` (Baileys) | `type` flat (`ReceivedCallback`, …) |
| `source_id` send | `key.id` | `messageId` |
| `source_id` receive | `key.id` | `messageId` |
| Mídia inbound | base64 ou download API | URL pública temporária |
| QR | webhook `QRCODE_UPDATED` + REST | `GET /qr-code/image` |
| Provisionamento | `POST /instance/create` local | Painel Z-API ou Partners API |
| Templates WABA | parcial via cloud path | ❌ |
| Grupos | configurável `groupsIgnore` | filtrar `isGroup` |

---

## O que NÃO fazer

- Reutilizar `EvolutionService` com flag `provider == zapi`
- Usar rota `/webhooks/evolution/:name` para Z-API
- Assumir `key.id` ou envelope `data.message`
- Esperar `MESSAGES_UPSERT` ou event bus único
- Persistir `api_key` Evolution no lugar de `instance_token`

---

## O que pode compartilhar

| Componente | Compartilhamento |
|------------|------------------|
| `MessagingProvider::Registry` | ✅ |
| prepend `Channel::Whatsapp` | ✅ padrão |
| prepend `WhatsappEventsJob` | ✅ com branch `zapi` |
| prepend `MessageWindowService` | ✅ |
| Wizard UX (steps, QR polling) | ✅ composable base |
| Specs pattern | ✅ `spec/custom/whatsapp/zapi/` |

---

## Coexistência no mesmo fork

Mesmo account Chatwoot pode ter:

- Inbox A → `provider: 'evolution'`
- Inbox B → `provider: 'zapi'`

Rotas webhook distintas: `/webhooks/evolution/:name` vs `/webhooks/zapi/:instance_id`.

---

## Quando escolher Z-API vs Evolution

| Critério | Preferir Z-API | Preferir Evolution |
|----------|----------------|-------------------|
| Ops / infra | Sem servidor próprio | Controle total self-host |
| Custo | Assinatura SaaS | Infra + manutenção |
| Webhook model | OK com demux `type` | Prefer event bus único |
| Customização Baileys | Limitada | Alta (settings, proxy, etc.) |

Ver também [../provider-comparison.md](../provider-comparison.md).
