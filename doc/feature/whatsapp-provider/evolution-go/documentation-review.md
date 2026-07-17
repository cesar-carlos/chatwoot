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
| [status.md](./status.md) | Estado | ✅ atualizado |
| [decisions.md](./decisions.md) | ADRs | ✅ §27 adicionado; webhook_token corrigido |
| [spec-design.md](./spec-design.md) | Contratos Ruby | ✅ ApiError, ConnectionChannel, controller, registry, job prepend |
| [tasks.md](./tasks.md) | Backlog | ✅ I0.6/I0.7, I1.1/I1.5/I1.6/I1.7 adicionados |
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Coexistência | ✅ seção collision adicionada |
| [api-reference.md](./api-reference.md) | Contratos REST | ✅ refresh_contacts, subscribe canônico (jul/2026) |
| [webhook-events.md](./webhook-events.md) | Payloads | ✅ filtros configuráveis + job prepend (jul/2026) |
| [provider-config-mapping.md](./provider-config-mapping.md) | JSONB | ✅ webhook_token corrigido |
| [error-handling.md](./error-handling.md) | Erros HTTP | ✅ sem alteração (bem documentado) |
| [implementation-plan.md](./implementation-plan.md) | Fases | ✅ webhook_token corrigido |
| [feature-mapping.md](./feature-mapping.md) | Paridade | ✅ webhook_token corrigido |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI | ✅ webhook_token corrigido |
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
| Avatar | `AVATAR_REQUEST_TIMEOUT=12s`; path `/user/avatar` sem retry; `evolution_go_avatar_attempted_at` + cooldown 6h |
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

**Escopo:** Revisão implementação edit (inbound/outbound) × OpenAPI Go × issues upstream; correção de drift documental (status ✅ demais otimista).

**Código (sem mudança nesta revisão):** `MessageEditPayloadExtractor`, `MessageEditSyncService`, `EditSyncService`, `EvolutionGoEditSync`, job ordering, fixtures `message_edit*.json`, specs unitários.

| Achado | Impacto doc |
|--------|-------------|
| API `POST /message/edit` existe e está wired | Confirmado em api-reference / documentation-links |
| Inbound edit depende de plaintext; Go 0.7+ frequentemente só `secretEncryptedMessage` | status/feature-mapping → ⚠️; webhook-events § Edit; troubleshooting; differences-from-evolution-api |
| `sync_edit_to_whatsapp` sem UI de editar no dashboard | ADR §35; provider-config / inbox-business-rules / validation-checklist |
| Anti-loop só na 1ª transição `edited_via_evolution_go_webhook` | troubleshooting + ADR §35 (risco residual) |

| Arquivo atualizado | Mudança |
|--------------------|---------|
| [status.md](./status.md) | Inbound edit ⚠️; próximo passo edit produto/Go |
| [feature-mapping.md](./feature-mapping.md) | Client/outbound edit ⚠️ + links #92 |
| [webhook-events.md](./webhook-events.md) | Seção Edit — formatos + encrypted skip |
| [troubleshooting.md](./troubleshooting.md) | Sintomas edit/plaintext/UI/re-sync |
| [provider-config-mapping.md](./provider-config-mapping.md), [inbox-business-rules.md](./inbox-business-rules.md), [business-rules-adaptation.md](./business-rules-adaptation.md) | Caveats flags |
| [validation-checklist.md](./validation-checklist.md), [api-reference.md](./api-reference.md), [README.md](./README.md) | Expectativas E2E / MVP |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | Row edit Node vs Go |
| [decisions.md](./decisions.md) | ADR §35 |
| [tasks.md](./tasks.md) | Follow-ups UX-9 / Go plaintext |

**Veredito:** implementação fork correta para o contrato disponível; **confiabilidade inbound edit em produção é ⚠️** até o Evolution Go entregar `editedMessage`.

**Follow-up código (mesma sessão):** anti-loop `EvolutionGoEditSync` reforçado; UI Edit (`MessageContentEditService`, `evolution_go_edit`, `MessageEditModal`, badge); tasks UX-9a/9b ✅.
