# Tarefas — Provider Evolution (delegação paralela)

**Atualizado:** jun/2026 · Fase 0–1 **implementada** no `custom/`

| ID | Tarefa | Agente | Status | Doc a atualizar |
|----|--------|--------|--------|-----------------|
| T0 | Validação spike Fase 1 vs `/root/evolution-api` (8080) + fixtures reais | spike-validation | ✅ feito | `validation-checklist.md`, `spec/fixtures/evolution/README.md`, `README.md` |
| T1 | Fase 2 backend — mídia in/out + statuses + reply quoted | phase2-backend | ✅ backend done (T2 sync/settings UI pendente) | `api-reference.md`, `webhook-events.md`, `implementation-plan.md` |
| T2 | Fase 2 frontend — settings inbox Evolution + sync | phase2-frontend | ✅ UI + inbound reopen/pending + ActionCable QR + cloud UI gates | `inbox-business-rules.md`, `provider-config-mapping.md` |
| T3 | Fase 3 — health, reconnect QR, logout/restart | phase3-ops | ✅ concluído | `implementation-plan.md`, `troubleshooting.md`, `decisions.md` |
| T4 | Fase 4 — import histórico (opcional) | — | ⏸️ aguardando T0–T3 | `implementation-plan.md` |
| T5 | Specs automatizados mínimos (`spec/custom/`) | — | ✅ feito | `spec-design.md`, este arquivo |

**Bugfix P0 (2026-06-20):** updates de runtime (`connection_status`, QR, `last_sender`) usam `update_columns` — não disparam `validate_provider_config` remoto nem `sync_settings`/`sync_proxy` em webhooks. Sync só quando `ProviderConfig::SYNCABLE_KEYS` mudam via save do inbox.

**P2 + P3 (2026-06-20):** mídia outbound via `MediaPayload` (base64 quando URL não é pública); create Evolution provisiona **após** inbox salvo; falha no provision remove inbox/channel local e `DELETE /instance/delete` na Evolution.

**Create hardening (2026-06-20):** `provision_evolution_channel!` faz cleanup em qualquer `StandardError`; `create` responde 422 com mensagem genérica para erros não-API.

---

## T5 — Specs automatizados (jun/2026)

**Arquivos:**

| Spec | Cobertura |
|------|-----------|
| `spec/custom/services/custom/whatsapp/webhooks/evolution_normalizer_spec.rb` | Fixture `messages_upsert_text` → normalizado; `messages_update_read` → status; filtros `ignore_jids`, `fromMe`, groups |
| `spec/custom/controllers/webhooks/evolution_controller_spec.rb` | Auth `apikey` match/mismatch; 404 instância desconhecida |
| `spec/custom/jobs/custom/webhooks/whatsapp_events_job_spec.rb` | `evolution_envelope?` routing + normalizer antes de `IncomingMessageService` |
| `spec/custom/services/custom/whatsapp/evolution/connection_service_spec.rb` | `#proxy_payload` → `{ enabled: false }` quando proxy desligado |

**Fixtures:** `spec/fixtures/evolution/` (carregados via `Rails.root.join`, não `file_fixture`).

**Run:** `bundle exec rspec spec/custom/services/custom/whatsapp/webhooks/evolution_normalizer_spec.rb spec/custom/controllers/webhooks/evolution_controller_spec.rb spec/custom/jobs/custom/webhooks/whatsapp_events_job_spec.rb spec/custom/services/custom/whatsapp/evolution/connection_service_spec.rb`

**Bugfix incluído:** `WhatsappEventsJob` prepend — `EvolutionNormalizer.new` passava args posicionais; corrigido para keywords `channel:` / `envelope:`.

---

## T0 — Validação spike (pré-fechar Fase 1)

**Objetivo:** executar [validation-checklist.md](./validation-checklist.md) contra Evolution local `http://localhost:8080` v2.3.6.

**Entregas:**
- Fixtures reais em `spec/fixtures/evolution/` (substituir sintéticos)
- `spec/fixtures/evolution/README.md` com formato sendText aceito e versão
- Marcar checklist em `validation-checklist.md` §7
- Corrigir bugs Fase 1 encontrados no spike
- Atualizar `README.md` tabela de estado se spike passar

**Env:** `BASE_URL=http://localhost:8080`, API key do `.env` Evolution

**Resultado (2026-06-20):** REST spike 1.1–1.4 ✅ contra v2.3.6; fixtures reais em `spec/fixtures/evolution/`; sendText aceita só `text` plano; bug `disable_chatwoot_integration` corrigido. E2E webhook/UI (§2–4 checklist) pendente — requer QR scan + Chatwoot rodando.

---

## T1 — Fase 2 backend

**Escopo** ([implementation-plan.md § Fase 2](./implementation-plan.md#fase-2--mídia-status-settings-completos)):

| # | Item | Arquivos |
|---|------|----------|
| 1 | `ApiClient#send_media`, `#send_audio` | `custom/.../api_client.rb` |
| 2 | `EvolutionService#send_attachment_message` | `custom/.../evolution_service.rb` |
| 3 | Normalizer — image, document, audio, video inbound | `custom/.../evolution_normalizer.rb` |
| 4 | `MESSAGES_UPDATE` → delivered/read no Chatwoot | normalizer + job |
| 5 | Outbound `quoted` (reply) no sendText | api_client + evolution_service |
| 6 | `sign_msg` / `sign_delimiter` outbound | evolution_service |
| 7 | `ignore_jids` configurável no normalizer | normalizer + provider_config |

**Referências:** [api-reference.md](./api-reference.md), [webhook-events.md](./webhook-events.md), [spec-design.md](./spec-design.md)

---

## T2 — Fase 2 frontend + sync settings

**Escopo:**

| # | Item | Arquivos |
|---|------|----------|
| 1 | Aba settings Evolution no inbox (groups_ignore, sign_msg, proxy, ignore_jids) | `custom/.../EvolutionSettings.vue` ou similar |
| 2 | Endpoint PATCH settings + `ConnectionService#sync_settings!` / `#sync_proxy!` | controller + connection_service |
| 3 | `reopen_conversation` / `conversation_pending` no inbound | ✅ `Conversations::Resolver` + `IncomingMessageServiceHelpers` + `Message` prepend |
| 4 | i18n EN | `inboxMgmt.json` |
| 5 | Mask `api_key` em serialização inbox | channel presenter se necessário |
| 6 | ActionCable QR/connection no wizard + health (polling fallback) | `EvolutionConnectionChannel`, `useEvolutionConnectionCable`, `Evolution.vue`, `EvolutionHealthPage.vue` |
| 7 | Gates cloud-only UI (`isEvolutionWhatsAppChannel`) | `ReplyBox`, `MessagesView`, `ConfigurationPage`, `ComposeNewConversationForm`, `inbox.js` |

**Padrão:** seguir Wavoip settings overlay em `custom/app/javascript/`

---

## T3 — Fase 3 operação

**Escopo:**

| # | Item |
|---|------|
| 1 | Health badge — `connectionState` no settings |
| 2 | Botões reconnect (QR), logout, restart instance |
| 3 | Alerta `CONNECTION_UPDATE` → `close` |
| 4 | `merge_brazil_contacts` no normalizer |
| 5 | `InstanceProvisioner` (fluxos avançados) — se escopo couber |

---

## Regras para todos os agentes

1. Código só em `custom/`; upstream mínimo com `# FORK:`
2. **Atualizar documentação** na pasta `doc/feature/whatsapp-provider/evolution-api/` ao concluir
3. Marcar status neste arquivo (`tasks.md`) ao finalizar
4. Não criar commits a menos que o usuário peça
5. Modelo: Composer 2.5

---

## Dependências

```
T0 (spike) ──┬──► T1 (backend mídia) ──► T2 (settings UI usa sync)
             └──► T3 (ops) — pode paralelizar com T1 após T0 parcial
T4 (import) — após E2E §2–4
T5 (specs) — ✅ 12 examples em `spec/custom/` (Evolution provider)
```

## Revisão (2026-06-20)

Auditoria completa do código Fase 0–3. Principais gaps: E2E §2–4. **Corrigido (2026-06-20):** `sync_proxy!` envia `{ enabled: false }` quando proxy desligado; `reopen_conversation` / `conversation_pending` inbound; mutex Evolution webhooks; defaults `convert_markdown_*` → false até Fase 2; ActionCable QR/connection no wizard + health; gates cloud-only UI via `isEvolutionWhatsAppChannel`; specs mínimos Evolution (T5); `EvolutionNormalizer.new` keywords no job prepend.
