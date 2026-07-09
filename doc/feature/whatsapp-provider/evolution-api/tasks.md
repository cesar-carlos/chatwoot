# Tarefas — Provider Evolution (delegação paralela)

**Atualizado:** jun/2026 · Fase 0–1 **implementada** no `custom/`

| ID | Tarefa | Agente | Status | Doc a atualizar |
|----|--------|--------|--------|-----------------|
| T0 | Validação spike Fase 1 vs `/root/evolution-api` (8080) + fixtures reais | spike-validation | ✅ feito | `validation-checklist.md`, `spec/fixtures/evolution/README.md`, `README.md` |
| T1 | Fase 2 backend — mídia in/out + statuses + reply quoted | phase2-backend | ✅ backend done (T2 sync/settings UI pendente) | `api-reference.md`, `webhook-events.md`, `implementation-plan.md` |
| T2 | Fase 2 frontend — settings inbox Evolution + sync | phase2-frontend | ✅ UI + inbound reopen/pending + ActionCable QR + cloud UI gates | `inbox-business-rules.md`, `provider-config-mapping.md` |
| T3 | Fase 3 — health, reconnect QR, logout/restart | phase3-ops | ✅ concluído | `implementation-plan.md`, `troubleshooting.md`, `decisions.md` |
| T4 | Fase 4 — import histórico | — | ✅ código (validação E2E pendente) | `implementation-plan.md` |
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
| 3 | `conversation_pending` no inbound; reabrir via `lock_to_single_conversation` | ✅ `Conversations::Resolver` + `IncomingMessageServiceHelpers` + `Message` prepend |
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
| 5 | `Provisioner` (create/webhook/settings) — `ConnectionEvents` para CONNECTION/QRCODE | ✅ |

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
T5 (specs) — ✅ ~42 examples em `spec/custom/` (Evolution provider) + Playwright em `tests/playwright/`
```

**Revisão (2026-06-21):** flags Fase 2 implementadas (`convert_markdown_*`, `mark_read_on_reply`, `notify_send_errors_private`, `sync_delete_to_whatsapp`); normalizer ampliado (sticker, location, contact, survey links); tile dedicado `ChannelList`; lookup JSONB corrigido no job; pairing code na UI; multi-attachment outbound.

**Revisão (2026-06-20):** auditoria Fase 0–3. Principais gaps: E2E §2–4. **Corrigido (2026-06-20):** `sync_proxy!` envia `{ enabled: false }` quando proxy desligado; `conversation_pending` inbound; mutex Evolution webhooks; defaults `convert_markdown_*` → false até Fase 2; ActionCable QR/connection no wizard + health; gates cloud-only UI via `isEvolutionWhatsAppChannel`; specs mínimos Evolution (T5); `EvolutionNormalizer.new` keywords no job prepend.

**Revisão (2026-06-21):** removido `provider_config.reopen_conversation` (duplicava `lock_to_single_conversation`); UI e `Custom::Conversations::Resolver` prepend eliminados.

**Revisão (2026-06-23):** docs alinhados com implementação — toggle reopen na `EvolutionSettingsPage` (seção Conversas); cache Redis Evolution N/A no provider nativo; `ResolutionCycle` considera `evolution_pending_since`; checklist §5.1 reopen E2E.

**Revisão (2026-06-22 — auditoria doc+código):**

| Item | Status |
|------|--------|
| `webhook-events.md` — tabela status Baileys corrigida | ✅ |
| Eventos `CONTACTS_*` documentados | ✅ |
| `ensure_chatwoot_integration_disabled!` com verificação `GET /chatwoot/find` | ✅ |
| Auth webhook `?token=` + `webhook_token` no provision | ✅ |
| Anexos parciais — nota privada em vez de `failed` | ✅ |
| Versão produção **2.3.7** alinhada em docs | ✅ |

**Revisão (2026-06-22 — pós-auditoria inbound):**

| Item | Status |
|------|--------|
| `EventNames` — `messages.upsert` → `MESSAGES_UPSERT` (controller + job) | ✅ |
| `WhatsappEventsJob` — log `[EVOLUTION] normalizer skipped` quando filtro retorna `nil` | ✅ |
| `resolve_wa_id` — `@lid` sem `addressingMode` usa `remoteJidAlt` | ✅ |
| Split `Provisioner` + `ConnectionEvents` (`ConnectionService` facade) | ✅ |
| `ApiClient.for_channel` | ✅ |
| `validate_provider_config?` exige `connectionState` → `open` | ✅ |

**Revisão (2026-06-24 — auditoria completa):**

| Item | Categoria | Status |
|------|-----------|--------|
| **Bug:** log `params[:instance]` no `WhatsappEventsJob` sempre vazio (controller envia `instance_name`) | bug | ✅ corrigido → `evolution_instance_name(params)` |
| **Bug:** `MessageEditSyncService` — `source_id` sintético com timestamp criava duplicatas se mesmo webhook disparasse 2× em segundos diferentes | bug | ✅ corrigido → suffix estável `-edited` |
| **Coupling:** `ConnectionEvents` usava `.send(:private_method)` em `ConnectionService` | acoplamento | ✅ corrigido → métodos `protected`; chamadas diretas |
| **Duplicação:** `outgoing_content`, `outgoing_media_message?`, `media_caption`, `extract_fallback_text`, `message_timestamp`, `enqueue_outgoing_media_download!` copiados em `PhoneOutgoingSyncService` e `Import::MessagesImporter` | duplicação | ✅ extraído → `OutgoingMessageHelper` |
| **God module:** `Custom::Message` misturava ciclo de conversa Evolution + sync delete + workflow rules (3 responsabilidades) | anti-pattern | ✅ dividido → `EvolutionConversationCycle` + `EvolutionDeleteSync` + `WorkflowRulesScheduler` |
| **Doc:** `sign_delimiter` documentado como implementado mas nunca lido pelo código | doc gap | ✅ implementado em `EvolutionServiceOutbound#sign_delimiter` (jun/2026) |
| **Doc:** lista de "sem toggle na UI" desatualizada — todos os campos agora expostos em `EvolutionSettingsPage.vue` | doc gap | ✅ atualizado em `inbox-business-rules.md` |
| **Doc:** proxy documentado como "Fase 2" em `api-reference.md` mas implementado desde Fase 1 | doc gap | ✅ corrigido em `api-reference.md` |
| **Doc:** ausência de aviso sobre suporte parcial a grupos (`groups_ignore: false`) | doc gap | ✅ adicionado em `inbox-business-rules.md` |

**Revisão (2026-06-24 — continuação):**

| Item | Categoria | Status |
|------|-----------|--------|
| `sign_delimiter` lido de `provider_config` em `EvolutionServiceOutbound` | funcionalidade | ✅ |
| `ContactEnrichmentJob` — lock in-flight liberado no `ensure` (retries Sidekiq funcionam) | bug | ✅ |
| `ContactEnrichmentService#fetch_and_apply_profile!` — não re-levanta após log (evita retry storm) | bug/perf | ✅ |
| `should_enqueue?` antes de enfileirar enrichment no `IncomingMessageIdentifierHelper` | perf | ✅ |
| `ContactsSyncService` — removido `runtime` Struct morto | cleanup | ✅ |
| `LostMessagesReconciliationService` — `known_source_id?` lazy (sem carregar 6h de msgs em memória) | perf | ✅ |

**Pontos abertos (não corrigidos nesta rodada):**

| Item | Categoria | Risco |
|------|-----------|-------|
| ~~Suporte a grupos completo~~ | funcionalidade | ✅ `GroupContactService`, metadata, inbound/outbound/import |
| ~~`validate_provider_config?` HTTP síncrono~~ | perf | ✅ cache 15s + rescues específicos |
| ~~Specs ausentes (lista auditoria)~~ | cobertura | ✅ ampliado em `spec/custom/` (jun/2026) |

**Revisão (2026-06-24 — plano melhorias Evolution):**

| Item | Categoria | Status |
|------|-----------|--------|
| Fase 1: `validate_provider_config?` cache 15s; QR throttle 45s; quoted N+1; MediaPayload SSRF | perf/bug | ✅ |
| Fase 2: `EvolutionMessageFilters` / `StatusMapper` / `PayloadBuilders`; `WebhookDispatcher` | refactor | ✅ |
| Fase 3: `find_group_infos`, `GroupMetadataService`, `GroupContactService`, inbound/outbound/import grupos; UI aviso experimental | funcionalidade | ✅ |
| Fase 4: specs `ApiClient`, `WebhookDispatcher`, grupos, jobs, `MediaAttachmentService`, `Broadcaster`, edit idempotency | cobertura | ✅ |
| Fase 5: checklist §5.1 reopen, proxy §6, import staging, Playwright — ver `validation-checklist.md` §7 | validação | ⏸️ manual/staging |

**Revisão (2026-06-21 — pós-produção):**

| Item | Status |
|------|--------|
| Modal QR (`EvolutionQrScanModal` + `useEvolutionQrSession`) | ✅ wizard + health |
| Help `AUTHENTICATION_API_KEY` + trim credenciais | ✅ |
| Anti-duplicata create (`isSubmitting` + `validate_evolution_instance_name_available!`) | ✅ |
| Segurança webhook (`apikey` fora do job Sidekiq; `ApiError#user_message`) | ✅ |
| Playwright `tests/playwright/` (API + UI create) | ✅ estrutura; credenciais reais no `.env` |
| Specs `spec/custom/` Evolution | ✅ ~42 examples |

**Revisão (2026-07-03 — confiabilidade Evolution API):**

| Item | Categoria | Status |
|------|-----------|--------|
| `MediaDownloadJob` — release lock Redis em `ensure` | bug P0 | ✅ |
| `MediaAttachmentService` — `ApiError` em HTTP não-2xx | bug P0 | ✅ |
| `ImportService` — lock Redis atômico (`EVOLUTION_IMPORT_LOCK`) | concorrência | ✅ |
| `MessageMutex` + reconciliação perdidas | dedup | ✅ |
| `GroupMetadataFetchJob` — metadata grupo fora do hot path | perf | ✅ |
| Cache `connection_validation` invalida em disconnect | cache | ✅ |
| `WebhookDispatcher` log `instance_name`; `import_failed_at` | observabilidade | ✅ |
| `PhoneOutgoingSync` `LockAcquisitionError`; `DeferredStatusJob` log exaustão | retry | ✅ |
| `RemoteJidFilter`; `contacts_importer` parsing defensivo | refactor | ✅ |
| `InboundMessageProcessor` desacopla dispatcher do job | refactor | ✅ |
| `evolutionCableRegistry` dedupe por inboxId | frontend | ✅ |
| Frontend: `EvolutionHealthPage` composable, QR modal cleanup, cable unificado, i18n | UX | ✅ |
| Docs: `webhook-events.md`, `decisions.md` §12/16, `spec-design.md` §6/11 | docs | ✅ |
| Specs ampliados (import lock, dispatcher, connection, reconciliation, deferred, JS cable/QR) | cobertura | ✅ |
| Smoke E2E checklist §2–4 (webhook inbound, QR, mídia outbound) | validação manual | ⏸️ requer Evolution + QR scan |

**Revisão (2026-07-09 — paridade inbound + typing):**

| Item | Categoria | Status |
|------|-----------|--------|
| Inbound `buttonsResponseMessage` / `templateButtonReplyMessage` / `listResponseMessage` → texto | bug/paridade Go | ✅ `payload_builders#interactive_reply_body` |
| `contextInfo` também em replies interativos | paridade | ✅ `CONTEXT_INFO_MESSAGE_KEYS` |
| Typing dashboard → `POST /chat/sendPresence` | funcionalidade | ✅ `PresenceSyncService` + `TypingListener` + `ApiClient#send_presence` |
| Doc: `spec-design` ainda dizia buttons/list deferidos | doc gap | ✅ alinhado com `sendButtons`/`sendList` |
| Doc: `api-reference` distingue `setPresence` (instância) vs `sendPresence` (chat) | doc | ✅ |
| Specs normalizer + presence + typing listener | cobertura | ✅ |

**Revisão (2026-07-09 — refresh manual de contatos):**

| Item | Categoria | Status |
|------|-----------|--------|
| `force: true` rebaixa avatar (purge + limpa hash/rate-limit) | bug | ✅ Node + Go enrichment |
| Go avatar via URL (`/user/avatar` → `data.URL`) em vez de base64 | bug | ✅ |
| `ContactsRefreshService` — todos os contatos do inbox | funcionalidade | ✅ |
| API `POST …/evolution_refresh_contacts` | transport | ✅ |
| Botão settings inbox "Refresh all contact profiles" | UI | ✅ |
| Lock Redis 30 min anti-duplicata | concorrência | ✅ |
