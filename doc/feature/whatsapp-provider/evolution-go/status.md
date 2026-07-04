# Status — Provider Evolution Go

**Escopo do fork:** integração Chatwoot ↔ Evolution Go (REST + webhooks).

**Última revisão:** 04/jul/2026 · **Fase 0–2 implementada (E2E pendente)**

---

## Resumo

| Área | Estado |
|------|--------|
| Fase 0 infra | ✅ |
| Fase 1 MVP texto + QR + health | ✅ |
| Fase 2 mídia, READ_RECEIPT, settings | ✅ |
| Gates UI (`isGatewayWhatsAppChannel`) | ✅ |
| Job prepend `to_prepare` (dev) | ✅ |
| Migration índice `instance_name` | ✅ (`schema.rb`) |
| E2E com instância operador | ⚠️ pendente |
| Fase 3 (interativos, presence) | ❌ |

---

## Implementado

### Backend
- `EvolutionGo::*` services (ApiClient, ConnectionService, SettingsSync, Media*)
- `EvolutionGoService` + outbound (text, media, quote, mark read on reply)
- `EvolutionGoNormalizer` (text + media), `EvolutionGoReadReceiptNormalizer`
- `READ_RECEIPT` no job prepend; `MarkReadService` ao abrir conversa
- `sync_settings!` / `sync_proxy!` (advanced-settings + delete proxy)
- `ignore_from_me_echo` respeitado no normalizer

### Frontend
- Wizard `EvolutionGo.vue` (server check, regex `instance_name`)
- `EvolutionGoSettingsPage.vue` (health + WhatsApp/outbound/proxy settings)
- `isGatewayWhatsAppChannel` / `isEvolutionGoWhatsAppChannel` gates
- ActionCable + polling QR

### Specs
- Normalizer (text + image), READ_RECEIPT, ApiClient (media/markread/download)
- Job (MESSAGE + READ_RECEIPT), service (quote), controller, collision

---

## Próximo passo

1. **E2E** — [validation-checklist.md](./validation-checklist.md) com servidor Go real (mídia download, READ_RECEIPT bruto)
2. **Fase 3** — poll, location, contact, sticker, presence
