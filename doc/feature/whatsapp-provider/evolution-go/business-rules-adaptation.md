# Regras de negócio adaptadas — Evolution Go

Defaults e comportamentos do inbox `provider: 'evolution_go'` no fork Chatwoot. Baseado em [../evolution-api/business-rules-adaptation.md](../evolution-api/business-rules-adaptation.md) com ajustes para API Go.

---

## Princípios

1. **Chatwoot é source of truth** para regras de conversa (`reopen_conversation`, templates como texto).
2. **Evolution Go** controla sessão WhatsApp (QR, proxy, ignore groups).
3. **Sem integração nativa Chatwoot** na Go — diferente da Evolution API Node.
4. **Provider separado** — não herdar defaults do Manager Evolution API sem revisar.

---

## Defaults fork (wizard seed)

| Campo | Default | Motivo |
|-------|---------|--------|
| `ignore_groups` | `true` | Chatwoot modela 1:1 |
| `ignore_status` | `true` | Ignorar status@broadcast |
| `reject_call` | `false` | Operador decide |
| `read_messages` | `false` | Não marcar lido automaticamente |
| `always_online` | `false` | Presença natural |
| `reopen_conversation` | `true` | UX suporte — conversa resolved reabre |
| `merge_brazil_contacts` | `true` | Fork BR |
| `sign_msg` | `false` | Chatwoot já mostra agente |
| `send_templates_as_text` | `true` | Sem WABA templates |
| `ignore_from_me_echo` | `true` | Evitar duplicação outbound |
| `proxy_enabled` | `false` | Opcional no wizard |

---

## Janela 24h e templates

| Regra Meta | Evolution Go | Ação fork |
|------------|--------------|-----------|
| Template fora de 24h | N/A | `MessageWindowService` → `nil` |
| Sync templates WABA | N/A | `sync_templates` noop |
| UI template picker | N/A | Ocultar para `evolution_go` |

---

## Proxy

| Fase | Comportamento |
|------|---------------|
| Fase 1 | Seção opcional no wizard — objeto `proxy` no `POST /instance/create` |
| Fase 2 | Editar via `advanced-settings` |

Campos: `address`, `port`, `username`, `password` (não `host`/`protocol` da Evolution API).

---

## Webhook e eventos

| Decisão | Valor |
|---------|-------|
| Eventos MVP | `MESSAGE`, `CONNECTION`, `QRCODE` |
| Auth | `webhook_secret` na query string |
| Retry Go | 5× / 30s — responder 200 rápido |

---

## Regras **não** portadas

| Regra Evolution API legada | Motivo |
|----------------------------|--------|
| `chatwoot.enabled: false` | Não existe endpoint `/chatwoot/set` |
| `WAID:` prefix em source_id | Legado Evolution→Chatwoot |
| `sign_msg` default ON (Manager) | Fork OFF |
| SQL import direto Postgres | Usar API/history-sync Fase 4 |

---

## UI — features ocultas

Para `isEvolutionGoWhatsAppChannel`:

- Embedded Signup Meta
- Template picker WABA
- Campanhas WhatsApp
- CSAT cloud
- Health Meta (`whatsapp_health_management`)
- Botão ligar (voz Meta)

---

## Paridade com Evolution API (fork)

| Regra | `evolution` | `evolution_go` |
|-------|-------------|----------------|
| Bypass 24h | ✅ | ✅ |
| Grupos ignorados MVP | ✅ | ✅ |
| Reopen conversation | ✅ | ✅ |
| Proxy wizard F1 | ✅ | ✅ |
| Webhook dedicado | `/webhooks/evolution/` | `/webhooks/evolution_go/` |
| Auth webhook | `apikey` body | `?token=` query |
