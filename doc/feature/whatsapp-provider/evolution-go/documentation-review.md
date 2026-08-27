# Revisão da documentação — Evolution Go (`evolution_go`)

---

## Histórico de revisões

| Data | Escopo |
|------|--------|
| 24/jun/2026 | Revisão inicial — comparação cruzada com código Evolution Node implementado; gaps G1–G7 identificados e corrigidos |
| 09/jul/2026 | Doc sync pós-implementação — status, coordination, feature-mapping |
| 12/jul/2026 | Auditoria doc × código — correção de drift em webhook-events, frontend-wizard-spec, subscribe lists, api-reference |
| 12/jul/2026 (pm) | `documentWithCaptionMessage` unwrap + troubleshooting n8n/`filename` |
| 12/jul/2026 (pm2) | Delete/edit: fromMe sync, SEND_MESSAGE ordering, ChatJid LID, outbound guards |
| 12/jul/2026 (pm3) | View-once `IsUnavailable` + i18n delete/view-once (en, pt, pt_BR) |
| 13/jul/2026 | Fixes operacionais: `stanzaID`, quote participant (`+55000` / `instance_name`), avatar backoff 6h, same-origin downloads |
| 16/jul/2026 | Auditoria doc × código — subscribe canônico, `conversation_pending` removido de Go, sync status/feature-mapping |
| 16/jul/2026 (pm) | Message reactions: inbound chip + outbound context menu; ADR §33; docs sync |
| 16/jul/2026 (eve) | Reactions improvements: ReactionsStore, user:self, timeout 15s, Node parity, cleanup rake |
| 16/jul/2026 (night) | Pseudo-forward Chatwoot-only; docs `doc/feature/message-forward/`; ADR §34 |
| 17/jul/2026 | Message edit audit: código × doc × Go [#92]; status/feature-mapping ⚠️ plaintext; ADR §35 |
| 17/jul/2026 (pm) | Doc sync × código: edit/delete contrato Go, enrichment/refresh paced, ADR §35–§36 |
| 18/jul/2026 | Meta AI `richResponseMessage` / `@bot` + unwrap `botInvokeMessage`; troubleshooting + checklist |
| 18/jul/2026 (pm) | Reactions: ChatJid prefere `@lid`; menu Reações expansível; optimistic `findStoreMessage`; E2E react OK |
| 18/jul/2026 | Sync contact MoreActions: `POST …/evolution_go_sync` + menu só Evolution Go |
| 18/jul/2026 | Avatar enrichment: LID-first + timeout cooldown 30m (`avatar_timeout_at`); [avatar-failures-report.md](./avatar-failures-report.md) |
| 18/jul/2026 | Sync contact: pt_BR i18n + poll 3× no MoreActions |
| 18/jul/2026 | Fix: `finalize_avatar_miss!` (cooldown só após fallback); poll timers clear on unmount |
| 18/jul/2026 | Sync force: 3× retry timeout/avatar, todos JIDs, `AvatarFromUrlJob.perform_now`, requeue se lock busy |
| 18/jul/2026 | Relatório avatar revalidado p/ handoff Evolution Go (P1–P4 + métricas + PTM controle) |
| 27/jul/2026 | Auditoria doc × código — endpoints Chatwoot incompletos, defaults resumidos, datas de sync |
| 27/jul/2026 (pm) | Bugfixes: delete sync-first, dedup lock protocol_only, QR session cancel/pairing clear, isReconnecting reset, enrichment force requeue cap |
| 27/jul/2026 (eve) | Group LID routing: `@g.us` never rewritten via `remoteJidAlt`; adapter omits group alt; device JID phone strip; Go participant enrichment |
| 27/jul/2026 (night) | Group avatar: `GroupMetadataService#warm_cache!` → `POST /user/avatar` com JID `@g.us` (não via `/group/info`) |
| 2/ago/2026 | Grupos: `GROUP_INFO`/`JOINED_GROUP` routing, `schedule_metadata_fetch!` dedup, naming `*(GROUP)`, automação/auto-assign skip, Sync contact branch, Vue sender label, fixtures reais |
| 27/ago/2026 | 1:1 LID vs PN: persistir addressing `@lid`; inbound LID-only; adapter prefere alt de telefone; ADR §37 |
| 27/ago/2026 (pm) | Dedup lock Evolution Go por inbox (dois canais da mesma conta); Unique ID vs `evolution_go_remote_jid`; ADR §38 |

---

## Revisão 27/ago/2026 — 1:1 LID vs PN

**Escopo:** Inbound 1:1 só `@lid` era dropado (`wa_id` vazio). Outbound texto/mídia ia para PN stale. `ChatJid` já preferia `@lid` no send (jul/2026) mas o inbound/echo gravava PN.

| Área | Decisão / código |
|------|------------------|
| Adapter | `peer_alt_jid` prefere JID de telefone ao `@lid` (SenderAlt/RecipientAlt). Grupos sem `remoteJidAlt` |
| Normalizer | `resolve_wa_id`: telefone do peer; senão `@lid` completo. `evolution_go_remote_jid` = addressing JID |
| Contato | `whatsapp_lid_inbound?` → `PeerContactInboxResolver`. Sem E.164 dos dígitos LID |
| Enrichment / echo | LID sobe por cima de PN; PN não regride LID |
| `ContactInbox` | `source_id` `@lid` só em `evolution_go` (espelha `@g.us`) |
| Docs | decisions §37, troubleshooting, webhook-events, feature-mapping, validation-checklist, status, inbox-business-rules |

**Fora de escopo:** Evolution Node; rake de backfill LID; grupos (`@g.us` continua primeiro).

---

## Revisão 27/ago/2026 (pm) — dedup lock por inbox

**Escopo:** Dois inboxes Evolution Go na mesma conta conversando. Eco `fromMe` no remetente e inbound no destinatário compartilhavam a mesma `source_id`. `MessageDedupLock` OSS é global — o eco engolia a bolha do outro canal (~20 ms, sem log).

| Área | Decisão / código |
|------|------------------|
| Lock | `Custom::Whatsapp::EvolutionGo::MessageDedupLock` — chave `inbox-{id}-{source_id}` |
| Inbound | `IncomingMessageEvolutionGo#lock_message_source_id!` |
| Echo | `PhoneOutgoingSyncService#acquire_dedup_lock!` |
| UI | Unique ID (`identifier`) pode ficar vazio; addressing LID em `evolution_go_remote_jid` |
| Docs | decisions §38, troubleshooting, webhook-events, error-handling, validation-checklist, status, README, feature-mapping, inbox-business-rules |

**Fora de escopo:** Cloud/Meta (lock OSS continua global); Evolution Node.

---

## Revisão 2/ago/2026 — grupos (correções + guards)

**Escopo:** Fechar gaps de metadata webhook, naming, automação, auto-assignment e Sync contact em grupos.

| Área | Decisão / código |
|------|------------------|
| Dispatcher | `GROUP` / `GROUP_INFO` / `JOINED_GROUP`; JID `data.JID`; `group_jid?` via `end_with?('@g.us')` |
| Metadata | `warm_cache_from_name!` (inline) + `schedule_metadata_fetch!` (Redis NX 5 min); API warm `force_avatar: true` |
| Naming | `should_update_group_name?` só `*(GROUP)`; create sem pushName do membro |
| Automação | `Custom::AutomationRuleListener` + `AutomationEventDispatcher` skip `@g.us` |
| Auto-assignment | `Custom::Conversation` + `Custom::AutoAssignment::AssignmentService` skip `@g.us` |
| Sync contact | Grupo → `GroupMetadataFetchJob`; 1:1 → enrichment; enrichment delega grupo a `warm_cache!` |
| UI | `useGroupMessageSender` + FORK em `Base.vue` |
| Docs | status, decisions §9, feature-mapping, api-reference, webhook-events, business-rules, differences |

---

## Revisão 27/jul/2026 (night) — group avatar

**Escopo:** Foto do contato-grupo WhatsApp.

| Item | Detalhe |
|------|---------|
| API | `/group/info` sem PictureURL; `/group/photo` é set-only; get via `/user/avatar` + `@g.us` |
| Código | `GroupMetadataService#sync_group_avatar!` (só `evolution_go`); skip se avatar já anexado; miss/timeout não falha o warm do nome |
| Attach | URL → `Avatar::AvatarFromUrlJob`; base64 → `Custom::Avatar::AvatarFromBase64Job` |

---

## Revisão 27/jul/2026 (eve) — group LID routing

**Escopo:** Mensagens de grupo “perdidas” / desviadas para 1:1 com `AddressingMode: lid`.

| Correção | Detalhe |
|----------|---------|
| `JidResolver` | Nunca preferir `remoteJidAlt` quando `remoteJid` é `@g.us`; `phone_from_jid` strip `:device` |
| `EvolutionGoPayloadAdapter` | Omitir `remoteJidAlt` em grupos; participant prefere `SenderAlt` |
| Job mutex | `outgoing_sender_id` usa JID completo do grupo |
| `GroupParticipantService` | Enrichment `EvolutionGo::*` quando provider é `evolution_go` |
| Specs / fixture | `message_inbound_group_lid.json` + normalizer/adapter/resolver |

Swagger Go confirma `AddressingMode` = `pn` \| `lid` no `MessageInfo`; LID não redefine o chat `@g.us`.

---

## Revisão 27/jul/2026 (pm) — bugfixes Evolution Go

**Escopo:** Correções dos 6 bugs da auditoria de implementação.

| Bug | Correção |
|-----|----------|
| Delete outbound inconsistente | `destroy` sync WA first (`raise_errors`); `@evolution_go_delete_synced_inline`; revert restaura `content` via `content_before_delete` |
| `isReconnecting` travado | Reset ao fechar modal QR sem conectar |
| Dedup lock protocol_only | `release_dedup_lock!` no early return |
| Pairing code stale | Limpa `pairingCode` ao aplicar novo QR |
| Poll órfão mid-flight | `sessionActive` + `sessionGeneration` em `useEvolutionGoQrSession` |
| Force enrichment requeue | Cap `force_retry_attempt` ≤ 3 |

---

## Revisão 27/jul/2026 — inventário endpoints / defaults

**Escopo:** Cruzamento `routes.rb` + `ProviderConfigDefaults` + controllers × docs de status/API/wizard.

**Veredito:** Integração alinhada com o código. Drift era só inventário documental (não comportamento).

| Arquivo | Drift corrigido |
|---------|-----------------|
| [status.md](./status.md) | API list incompleta (`refresh_contacts`, `react`, `edit`, `evolution_go_sync`); defaults resumidos vs `ProviderConfigDefaults` |
| [api-reference.md](./api-reference.md) | Faltavam `evolution_go_edit` e `contacts/:id/evolution_go_sync` |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | Tabela dashboard sem react/edit/sync contact |
| [provider-config-mapping.md](./provider-config-mapping.md) | `sign_delimiter`, `send_random_delay`, `notify_send_errors_private` no Grupo 5 + JSON seed |
| [feature-mapping.md](./feature-mapping.md) / [README.md](./README.md) | Datas de sync → 27/jul |

**Sem mudança de comportamento.** Pendências operacionais inalteradas: E2E, fixtures reais, poll/link, proxy edit, Go [#92](https://github.com/evolution-foundation/evolution-go/issues/92).

---

## Revisão 24/jun/2026

**Escopo:** 22 arquivos em `evolution-go/` + código `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` + `custom/config/initializers/messaging_provider_registry.rb`

**Fontes:** código Evolution Node implementado (60+ arquivos em `custom/`), collection Postman, OpenAPI evolution-go

---

## Veredito executivo

| Dimensão | Nota | Comentário |
|----------|------|------------|
| Cobertura API / webhooks | **A** | 26 ADRs + Postman audit cobrindo todos os endpoints MVP |
| Alinhamento fork Node implementado | **B−** | Gaps críticos encontrados na detecção de envelope e registry |
| Prontidão para codificar Fase 0 | **B** | Bloqueado por G4 (prepend collision) e G6 (webhook_token) até correção |
| Completude vs z-api (peer) | **B+** | Tem `error-handling.md` e `troubleshooting.md` que z-api não tem |
| Fixtures E2E | **⚠️** | Templates sintéticos — confirmar com instância real |

---

## Gaps identificados e corrigidos

| # | Gap | Gravidade | Arquivo(s) corrigido(s) |
|---|-----|-----------|------------------------|
| G1 | `EvolutionGo::ApiError` ausente do spec-design e tasks | Alta | `spec-design.md`, `tasks.md` |
| G2 | `EvolutionGoConnectionChannel` (ActionCable) ausente do spec-design e tasks | Alta | `spec-design.md`, `tasks.md` |
| G3 | `EvolutionGoController` spec sem `process_payload` e `sanitized_job_payload` | Alta | `spec-design.md` |
| G4 | **CRÍTICO** — prepend collision: evolution Node `return` (sem `super`) silencia eventos Go; mesma `evolution_envelope?` captura ambos os providers | **Crítica** | `decisions.md` (§27), `spec-design.md`, `tasks.md` (I0.7), `coordination-with-evolution-api.md` |
| G5 | Registry format errado no spec — bloco vs posicional (código real usa posicional) | Alta | `spec-design.md` |
| G6 | `webhook_secret` inconsistente com evolution Node implementado (`webhook_token`) | Alta | Todos os 10 arquivos afetados (sed replace) |
| G7 | Migration para índice único `instance_name` ausente de Fase 0 tasks | Média | `tasks.md` (I0.6) |

---

## Detalhamento — G4 (prepend collision)

O `Custom::Webhooks::WhatsappEventsJob` implementado:

```ruby
def evolution_envelope?(params)
  params[:event].present? && evolution_instance_name(params).present?
end

def evolution_instance_name(params)
  params[:instance_name].presence || params[:instance]
end
```

Evolution Go tem **o mesmo envelope** (`event` + `instance`). Sem cuidado:

1. Evolution_go controller injeta `instance_name: params[:instance_name]` (como evolution node)
2. `evolution_envelope?` → true para eventos Go
3. `find_evolution_channel` (procura `provider: 'evolution'`) → nil
4. `unless channel ... return` — **descarte silencioso**, nunca chama `super`

**Fix documentado em decisions.md §27:**
- Controller Go injeta `evolution_go_instance_name:` (não `instance_name:`) e remove `instance` do payload bruto
- Prepend Go detecta por `params[:evolution_go_instance_name].present?`
- Prepend Node: `return super(params)` (não `return`) no guard canal não encontrado — task I0.7

---

## Inventário por arquivo

| Arquivo | Papel | Estado após revisão |
|---------|-------|---------------------|
| [README.md](./README.md) | Landing | ✅ |
| [status.md](./status.md) | Estado | ✅ atualizado 27/jul/2026 |
| [decisions.md](./decisions.md) | ADRs | ✅ §27 adicionado; webhook_token corrigido |
| [spec-design.md](./spec-design.md) | Contratos Ruby | ✅ ApiError, ConnectionChannel, controller, registry, job prepend |
| [tasks.md](./tasks.md) | Backlog | ✅ I0.6/I0.7, I1.1/I1.5/I1.6/I1.7 adicionados |
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Coexistência | ✅ seção collision adicionada |
| [api-reference.md](./api-reference.md) | Contratos REST | ✅ refresh_contacts, edit, sync contact, subscribe canônico (27/jul/2026) |
| [webhook-events.md](./webhook-events.md) | Payloads | ✅ filtros configuráveis + job prepend (jul/2026) |
| [provider-config-mapping.md](./provider-config-mapping.md) | JSONB | ✅ defaults + `sign_delimiter` (27/jul/2026) |
| [error-handling.md](./error-handling.md) | Erros HTTP | ✅ sem alteração (bem documentado) |
| [implementation-plan.md](./implementation-plan.md) | Fases | ✅ webhook_token corrigido |
| [feature-mapping.md](./feature-mapping.md) | Paridade | ✅ webhook_token corrigido |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI | ✅ endpoints react/edit/sync contact (27/jul/2026) |
| [inbox-business-rules.md](./inbox-business-rules.md) | Regras | ✅ webhook_token corrigido |
| [validation-checklist.md](./validation-checklist.md) | E2E | ⚠️ não executado — próximo passo operacional |
| [troubleshooting.md](./troubleshooting.md) | Runbook | ✅ webhook_token corrigido |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | Comparativo | ✅ sem alteração |
| [postman-validation.md](./postman-validation.md) | Audit | ✅ sem alteração |

---

## Diferenças intencionais vs z-api (peer)

| Aspecto | Evolution Go | Z-API | Notas |
|---------|-------------|-------|-------|
| `error-handling.md` | ✅ | ❌ | Evolution Go tem runbook de erros |
| `troubleshooting.md` | ✅ | ❌ | Z-API cria após piloto |
| `ConnectionEvents` separado | ✅ `EvolutionGo::ConnectionEvents` | ✅ | Alinhado com Node/Z-API |
| `Broadcaster` dedicado | ✅ | ❌ | `EvolutionGo::Broadcaster` + disconnect toast |

---

## Revisão jul/2026 (pós-implementação + review)

| Área | Ação |
|------|------|
| `webhook-events.md` | SEND_MESSAGE echo sync, EventNames, aliases, canonical subscribe |
| `decisions.md` | §7/§18/§25 updated; ADR §28–§31 (echo, EventNames, latency, SSRF) |
| `provider-config-mapping.md`, `inbox-business-rules.md` | Proxy `host` not `address` |
| `troubleshooting.md`, `status.md`, `README.md` | Sync with current behavior |
| `api-reference.md`, `postman-validation.md`, `spec-design.md`, `frontend-wizard-spec.md` | ✅ alinhados jul/2026 |
| Código | 23 review items: P1–P3 fixes applied jul/2026 |

---

## Revisão 09/jul/2026 (doc sync vs código)

Cruzamento código `custom/.../evolution_go/` × docs. **Conclusão:** docs de status/tasks estavam majoritariamente corretos; vários docs de *planejamento* ainda descreviam Go como “só documentação” ou features já shipped como Fase 3.

| Arquivo | Drift | Correção |
|---------|-------|----------|
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | “Estado Go: somente documentação”; PROVIDERS sem `evolution_go`; registry em bloco; `EvolutionGoWhatsapp` / `useGatewayWhatsappWizard` | Reescrito para estado implementado |
| [feature-mapping.md](./feature-mapping.md) | Location/contact/sticker/logout ainda “Fase 3” | Marcados ✅ / parcial |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | Nome `EvolutionGoWhatsapp.vue`; composable compartilhado como se existisse | Nomes reais + nota “não implementado” |
| [decisions.md](./decisions.md) §11 | Wizard ADR desatualizado | Aponta `EvolutionGo.vue` + composables dedicados |
| [README.md](./README.md) / [status.md](./status.md) / [tasks.md](./tasks.md) | Escopo “planejado”; API inbox incompleta; I3 ❌ | Ajustados |

| Aspecto planejado | Código real |
|-------------------|-------------|
| `ConnectionEvents` inline no `ConnectionService` | ✅ classe separada `EvolutionGo::ConnectionEvents` |
| `useGatewayWhatsappWizard` | ❌ não existe — composables `evolution_go/*` |
| `EvolutionGoWhatsapp.vue` | `EvolutionGo.vue` |

---

## Revisão 12/jul/2026 (doc × código — correções aplicadas)

**Escopo:** Cruzamento `custom/.../evolution_go/` × 12 arquivos de documentação com drift identificado.

**Veredito:** Integração implementada (fases 0–4). Documentação de **status** já estava alinhada; contratos técnicos de **planejamento** ainda descreviam MVP Fase 1.

| Arquivo | Drift corrigido |
|---------|-----------------|
| [webhook-events.md](./webhook-events.md) | Filtros "hardcoded" → `ignore_from_me_echo` / `ignore_groups`; job prepend completo |
| [provider-config-mapping.md](./provider-config-mapping.md) | Subscribe mínimo → lista canônica `WEBHOOK_EVENTS` |
| [troubleshooting.md](./troubleshooting.md) | Subscribe reconnect → lista canônica |
| [validation-checklist.md](./validation-checklist.md) | `WEBHOOK_SECRET` → `WEBHOOK_TOKEN`; subscribe canônico |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | Rotas API reais; 2 telas + modal; i18n `inboxMgmt.json`; critérios ✅ |
| [api-reference.md](./api-reference.md) | `evolution_go_refresh_contacts`; subscribe connect; presence implementado; Bearer auth |
| [feature-mapping.md](./feature-mapping.md) | `/send/button` (singular); wizard form+modal |
| [spec-design.md](./spec-design.md) | Job prepend, Bearer auth, paths de spec reais |
| [inbox-business-rules.md](./inbox-business-rules.md) | Escopo por fase → tabela implementado |
| [README.md](./README.md) | Fases 0–4; refresh contacts |

**Ainda pendente (não bloqueante):** E2E operador, fixtures JSON reais, `evolution-target-version.txt` preenchido.

| Item | Bloqueio | Ação |
|------|----------|------|
| Fixtures JSON reais | Sem instância Go | [validation-checklist.md](./validation-checklist.md) E2E |
| JID field real no `GET /instance/status` | Formato Go não confirmado | Capturar no E2E |
| `CONNECTION` payload real | Template sintético | `connection_event.json` E2E |
| Presence → typing dashboard | ✅ | `TypingListener` + `PresenceSyncJob` + `ApiClient#set_presence` |
| Versão Go congelada | Operador informa | `evolution-target-version.txt` |

---

## Revisão 12/jul/2026 (pm) — documentWithCaptionMessage

**Escopo:** Bug n8n/PDF → Chatwoot mostrava `[Unsupported message type]` no echo de `POST /send/media` com caption.

| Arquivo | Drift corrigido |
|---------|-----------------|
| [webhook-events.md](./webhook-events.md) | Wrappers aninhados (`documentWithCaptionMessage`, ephemeral, viewOnce) |
| [troubleshooting.md](./troubleshooting.md) | Sintomas unsupported + payload n8n (`filename`, url HTTPS/base64) |
| [api-reference.md](./api-reference.md) | Nota `filename` + echo webhook wrapped |
| Código | `EvolutionGoPayloadAdapter#unwrap_nested_message` + specs |

---

## Revisão 12/jul/2026 (pm2) — delete/edit sync

**Escopo:** Gaps em delete/edit (cliente, celular, Chatwoot → WA).

| Arquivo / código | Correção |
|------------------|----------|
| Job `process_send_message_event` | Delete/edit **antes** de `ignore_from_me_echo` |
| `MessageDeleteSyncService` / `MessageEditSyncService` | Aplicam `fromMe` (soft-delete/edit outgoing); edit skip noop + não inventa incoming |
| `DeleteSyncService` / hook | Guard `outgoing?` |
| `ChatJid` | Resolve LID em `contact.additional_attributes` |
| `EditSyncService` | Markdown outbound + `sign_msg` |
| `EvolutionGoEditSync` | Skip loop quando edit veio do webhook |
| `WEBHOOK_EVENTS` | Inclui `SEND_MESSAGE_UPDATE` |
| `HistorySyncProcessor` | Protocol delete/edit no import |
| [webhook-events.md](./webhook-events.md), [provider-config-mapping.md](./provider-config-mapping.md), [inbox-business-rules.md](./inbox-business-rules.md), [validation-checklist.md](./validation-checklist.md), [status.md](./status.md) | Docs alinhados |

---

## Revisão 12/jul/2026 (pm3) — view-once unavailable + delete UX i18n

**Escopo:** Mídia view once indisponível no webhook; avisos de delete/view-once em pt/pt_BR.

| Arquivo / código | Correção |
|------------------|----------|
| `EvolutionGoPayloadAdapter` | Preserva `IsUnavailable` / `UnavailableType` no canonical |
| `EvolutionGoNormalizer` | `type: unsupported` + `evolution_go_unavailable_type` |
| `IncomingMessageEvolutionGo#create_unsupported_message` | Placeholder via I18n (`view_once_unavailable`) + `is_unsupported` / `unavailable_type` |
| `Unsupported.vue` / `Base.vue` | Bubble view-once + delete notice (camelCase attrs); `// FORK:` |
| Locales | `en` + `pt` / `pt_BR` (`VIEW_ONCE_MEDIA_UNAVAILABLE`, `DELETED_*_NOTICE`) |
| [webhook-events.md](./webhook-events.md), [troubleshooting.md](./troubleshooting.md), [inbox-business-rules.md](./inbox-business-rules.md), [validation-checklist.md](./validation-checklist.md), [status.md](./status.md) | Docs alinhados |

---

## Revisão 13/jul/2026 — replies / avatars / alias hosts

**Escopo:** Commit `fix(fork): Evolution Go replies/avatars and alias-host downloads`.

| Área | Comportamento real |
|------|-------------------|
| Reply inbound | `contextInfo.stanzaID` (whatsmeow) + `stanzaId` (Baileys) |
| Quote outbound | `quoted.participant` para mensagem própria: JID do negócio via `instance_name` quando `phone_number` é placeholder `+55000…` |
| Avatar | `AVATAR_REQUEST_TIMEOUT=12s`; path `/user/avatar` sem retry; `avatar_attempted_at` 6h (sem foto); `avatar_timeout_at` 30m (timeout) |
| Downloads UI | `sameOriginActiveStorageUrl` — rewrite Active Storage para origin atual em hosts alias |

Docs tocados no commit: [troubleshooting.md](./troubleshooting.md), [webhook-events.md](./webhook-events.md).

---

## Revisão 16/jul/2026 — auditoria doc × código

**Veredito:** Integração alinhada com o código. Drift residual era documental (não de implementação).

| Arquivo | Drift corrigido |
|---------|-----------------|
| [inbox-business-rules.md](./inbox-business-rules.md) | Subscribe ainda MVP legado; `conversation_pending` documentado mas **não** existe em Go |
| [provider-config-mapping.md](./provider-config-mapping.md) | Removido `conversation_pending` do grupo Conversas |
| [business-rules-adaptation.md](./business-rules-adaptation.md) | Eventos MVP → lista canônica |
| [api-reference.md](./api-reference.md) / [troubleshooting.md](./troubleshooting.md) | Subscribe sem `SEND_MESSAGE_UPDATE` |
| [feature-mapping.md](./feature-mapping.md) / [status.md](./status.md) | Sync 13/jul (stanzaID, avatar backoff, quote participant) |
| [decisions.md](./decisions.md) | ADR §32 avatar backoff + quote JID |

**Ainda pendente (não bloqueante):** E2E operador, fixtures JSON reais, `evolution-target-version.txt` preenchido.

---

## Revisão 16/jul/2026 (pm) — message reactions

**Escopo:** Implementação completa reactions `evolution_go` (inbound chip + outbound context menu).

| Área | Entrega |
|------|---------|
| Inbound | `MessageReactionPayloadExtractor` + `MessageReactionSyncService`; job hook; sem placeholder |
| Outbound | `ApiClient#react`, `ReactSyncService`, rota `evolution_go_react`, context menu |
| UI | Chip em `Base.vue`; i18n EN |
| Docs | ADR §33, webhook-events, feature-mapping, status, troubleshooting, validation-checklist |

## Revisão 16/jul/2026 (eve) — reactions improvements

**Escopo:** Pós-MVP — `ReactionsStore` + `user:self`, timeout 15s, chip clicável, optimistic UI, rake cleanup, paridade Node.

| Área | Entrega |
|------|---------|
| Store | `Custom::Whatsapp::ReactionsStore` shared |
| Go | Timeout `/message/react` 15s; bump `last_activity_at` |
| Node | Extractor/Sync/ReactSync + `send_reaction`; placeholder removido |
| UX | Chip highlight/remove; optimistic context menu |
| Ops | `rake evolution_go:cleanup_reaction_placeholders` |
| Docs | ADR §33 addendum + fixture `message_reaction.json` |

## Revisão 16/jul/2026 (night) — pseudo-forward

**Escopo:** Encaminhar mensagem Chatwoot-only (sem API Go); documentação feature completa.

| Área | Entrega |
|------|---------|
| Código | `useMessageForward` + `MessageForwardModal`; FORK menu/Message/Base |
| ADR | §34 em decisions.md |
| Docs | Pasta [`doc/feature/message-forward/`](../../message-forward/) (README, current-state, decision-tree, ui-design, plan, backlog) |
| Cross-links | evolution-go README, feature-mapping, validation-checklist, status |

---

## Revisão 17/jul/2026 — message edit audit

**Escopo:** Revisão implementação edit (inbound/outbound) × OpenAPI Go × issues upstream.

**Follow-up 17/jul pm:** alinhamento ao contrato Go plaintext (`IsEdit` / `editedMessage` / `extendedTextMessage`); revoke vs `Info.Edit`; delete revert; doc sync.

| Achado | Estado atual |
|--------|--------------|
| API `POST /message/edit` `{ chat, messageId, message }` | ✅ wired |
| UI Edit + anti-loop sempre-on-flag | ✅ |
| Inbound plaintext protocol | ✅ |
| Envelope `secretEncryptedMessage` sem texto | ⚠️ skip residual ([#92](https://github.com/evolution-foundation/evolution-go/issues/92)) |

**Veredito (atualizado):** fork alinhado ao contrato Go com plaintext; encrypted-only permanece skip. Outbound edit/delete + UI ✅.

Arquivos de referência: [status.md](./status.md), [webhook-events.md](./webhook-events.md) § Edit/Revoke, [decisions.md](./decisions.md) §35–§36, [troubleshooting.md](./troubleshooting.md).
