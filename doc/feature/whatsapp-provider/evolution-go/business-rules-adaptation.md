# Regras de negócio adaptadas — Evolution Go

Defaults e comportamentos do inbox `provider: 'evolution_go'` no fork Chatwoot. Baseado em [../evolution-api/business-rules-adaptation.md](../evolution-api/business-rules-adaptation.md) com ajustes para API Go.

---

## Princípios

1. **Chatwoot é source of truth** para regras de conversa (`lock_to_single_conversation`, templates como texto).
2. **Evolution Go** controla sessão WhatsApp (QR, proxy, ignore groups).
3. **Sem integração nativa Chatwoot** na Go — diferente da Evolution API Node.
4. **Provider separado** — não herdar defaults do Manager Evolution API sem revisar.

---

## Defaults fork (wizard seed)

| Campo | Default | Motivo |
|-------|---------|--------|
| `ignore_groups` | `true` | Default 1:1; com `false`, grupos viram conversa única por JID |
| `ignore_status` | `true` | Ignorar status@broadcast |
| `reject_call` | `false` | Operador decide |
| `read_messages` | `false` | Não marcar lido automaticamente |
| `always_online` | `false` | Presença natural |
| Reabrir conversa resolvida | `inbox.lock_to_single_conversation: true` | UX suporte — não duplicar em `provider_config` |
| `merge_brazil_contacts` | `true` | Fork BR |
| `sign_msg` | `false` | Chatwoot já mostra agente |
| `send_templates_as_text` | `true` | Sem WABA templates |
| `ignore_from_me_echo` | `true` | Evitar duplicação outbound |
| `proxy_enabled` | `false` | Opcional no wizard |
| `mark_inbound_deleted` | `true` | Refletir delete do cliente **e** do celular/agente no Chatwoot |
| `mark_inbound_edited` | `true` | Refletir edit do cliente **e** do celular/agente no Chatwoot **quando houver plaintext**; encrypted-only → skip ([#92](https://github.com/evolution-foundation/evolution-go/issues/92)) |
| `import_on_connect` | `false` | Import manual/opt-in (evita carga ao conectar) |
| `convert_markdown_inbound` | `true` | Paridade Evolution API |
| `sync_delete_to_whatsapp` | `false` | Irreversível — opt-in explícito |
| `sync_edit_to_whatsapp` | `false` | Opt-in; UI Edit no context menu (`evolution_go_edit`) |

> **Inboxes existentes** mantêm valores já salvos; defaults acima aplicam-se apenas a **novos** inboxes.

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
| Fase 2 | Remover via `DELETE /instance/proxy/{id}`; **editar host/porta exige recriar instância** (banner na UI) |

Campos: `host`, `port`, `protocol`, `username`, `password`. `POST /instance/proxy/{instanceId}` exists for post-create updates (fork still requires recreate for settings UI proxy changes).

---

## Webhook e eventos

| Decisão | Valor |
|---------|-------|
| Eventos subscribe | Lista canônica `ProviderConfig::WEBHOOK_EVENTS` (+ `GROUP` se `ignore_groups: false`) |
| Auth | `webhook_token` na query string |
| Retry Go | 5× / 30s — responder 200 rápido |

---

## Regras **não** portadas

| Regra Evolution API legada | Motivo |
|----------------------------|--------|
| `chatwoot.enabled: false` | Não existe endpoint `/chatwoot/set` |
| `WAID:` prefix em source_id | Legado Evolution→Chatwoot |
| `sign_msg` default ON (Manager) | Fork OFF |
| SQL import direto Postgres | Usar API/history-sync Fase 4 |
| Editar proxy após create | Recriar instância — sem `advanced-settings` proxy validado |

---

## Grupos WhatsApp

| `ignore_groups` | Comportamento |
|-----------------|---------------|
| `true` / `nil` / ausente (default) | Mensagens `@g.us` filtradas (`config['ignore_groups'] != false`) |
| `false` | Uma conversa por grupo; `ContactInbox#source_id` = JID `@g.us`; nome via `POST /group/info` (`GroupMetadataService`); remetente em `evolution_go_participant_jid` / `push_name` |

Paridade com Evolution API: reutiliza `GroupContactService`, `GroupParticipantService`, `GroupMetadataFetchJob`.

**Regras fork (grupos habilitados):**

- Nome do contato: só sobrescreve com `*(GROUP)`; create não usa pushName do membro
- Webhooks `GroupInfo` / `JoinedGroup`: warm inline + fetch deduplicado (`schedule_metadata_fetch!`, lock 5 min)
- Automações e auto-assignment (inbox + Assignment V2) **não** rodam em `@g.us`
- Sync contact (MoreActions): grupo → `/group/info` + avatar `@g.us`; 1:1 → enrichment

**Limitações:** conversas 1:1 criadas antes de habilitar grupos não se fundem automaticamente; mensagens de automação já persistidas em threads de grupo não são apagadas.

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
| Grupos ignorados (default) | ✅ | ✅ |
| Grupos como conversa (`ignore_groups: false`) | ✅ | ✅ |
| Reopen conversation | ✅ | ✅ |
| Proxy wizard F1 | ✅ | ✅ |
| Webhook dedicado | `/webhooks/evolution/` | `/webhooks/evolution_go/` |
| Auth webhook | `apikey` body | `?token=` query |
