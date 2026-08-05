# Decisões fechadas — Provider Evolution Go

Decisões de implementação registradas para evitar retrabalho. **Status:** aprovado para implementação (jun/2026). Confirmar payloads no E2E com instância do operador ([validation-checklist.md](./validation-checklist.md)).

---

## 1. Rota webhook

| Decisão | Valor |
|---------|-------|
| **Rota** | `POST /webhooks/evolution_go/:instance_name` |
| **Controller** | `Custom::Webhooks::EvolutionGoController` |
| **Job** | `Webhooks::WhatsappEventsJob` (prepend) |

**Motivo:** distinto de `/webhooks/evolution/:instance_name` (Evolution API Node) — evita colisão se operador rodar ambos.

**URL registrada no connect:**

```
https://{FRONTEND_URL}/webhooks/evolution_go/{instance_name}
```

Configurar em `ConnectionService#connect` via body `webhookUrl` — **não** existe `POST /webhook/set`.

---

## 2. Autenticação do webhook

| Decisão | Valor |
|---------|-------|
| **Método primário** | Query `?token=` com secret gerado no create do inbox |
| **Método secundário** | Header `Authorization: Bearer {webhook_token}` — implementado em `EvolutionGoController` |
| **Envelope `apikey`** | **Não disponível** no body Go — diferente da Evolution API |

```ruby
# EvolutionGoController#authenticate_webhook!
def authenticate_webhook!
  channel = find_channel_by_instance_name(params[:instance_name])
  return head :not_found unless channel

  secret = channel.provider_config['webhook_token'].to_s.strip
  query_token = params[:token].to_s.strip
  bearer = request.headers['Authorization'].to_s.remove(/^Bearer /i).strip
  provided = query_token.presence || bearer

  return head :unauthorized unless secret.present? &&
    provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

  @channel = channel
end
```

Registrar URL completa: `#{FRONTEND_URL}/webhooks/evolution_go/#{name}?token=#{webhook_token}`

---

## 3. Resolução do channel no job

| Decisão | Valor |
|---------|-------|
| **Lookup** | `provider = 'evolution_go'` e `provider_config->>'instance_name' = :instance_name` |
| **Regra** | **1 instância Go = 1 inbox** |

Índice recomendado (migration fork):

```ruby
add_index :channel_whatsapp, "(provider_config->>'instance_name')",
          unique: true,
          where: "provider = 'evolution_go'",
          name: 'index_channel_whatsapp_evolution_go_instance_name'
```

`phone_number` obrigatório após `GET /instance/status` → `data.myJid`.

---

## 4. Autenticação REST — duas chaves

| Decisão | Valor |
|---------|-------|
| **`global_api_key`** | Operações admin: create, list, delete |
| **`instance_token`** | Connect, QR, status, send |
| **Wizard** | Operador informa `base_url` + `global_api_key`; após create, persiste `instance_token` |

Alternativa: operador cria instância no painel Go e cola `instance_token` no wizard (modo "instância existente").

---

## 5. Formato `sendText` — path e body

| Decisão | Valor |
|---------|-------|
| **Path** | `POST /send/text` — confirmado OpenAPI oficial |
| **Body** | `{ "number": "...", "text": "..." }` |
| **Header** | `apikey: instance_token` |
| **Quoted** | `{ quoted: { messageId, participant } }` — schema Go, não Baileys `quoted.key` |

Doc: [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message)

---

## 6. `source_id` outbound

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `response.dig('data', 'Info', 'ID')` — struct whatsmeow PascalCase |
| **Fallback** | `response.dig('data', 'messageId')` se presente |
| **Não usar** | `key.id` (formato Baileys/Evolution API Node) |

---

## 7. Echo `fromMe` / `SEND_MESSAGE`

| Decisão | Valor |
|---------|-------|
| **Default** | `ignore_from_me_echo: true` — drop echo events |
| **Opt-in** | When `false`, `SEND_MESSAGE` and `MESSAGE` with `fromMe: true` → `PhoneOutgoingSyncService` (outgoing, `phone_sent: true` + `external_echo: true` for native-app UI) |
| **Contact** | `PeerContactInboxResolver` reuses existing conversations |

---

## 8. Janela 24h e templates

| Decisão | Valor |
|---------|-------|
| **Janela** | `MessageWindowService` prepend → `nil` para `evolution_go` |
| **Templates** | `send_templates_as_text: true` — viram `send_text` |
| **UI** | Ocultar features cloud-only |

Reusar prepend da Fase 0 com capability `unlimited_session: true`.

---

## 9. Grupos WhatsApp

| Decisão | Valor |
|---------|-------|
| **Default** | `ignore_groups: true` (nil/ausente = ignorar — predicado `!= false` no job, normalizer, phone sync, subscribe, import) |
| **Opt-in** | `ignore_groups: false`: conversa única por JID `@g.us`; nome via `POST /group/info`; participante em `evolution_go_participant_*` |
| **Subscribe** | Categoria `GROUP` → eventos `GroupInfo` / `JoinedGroup` (`data.JID`); job aceita `GROUP` / `GROUP_INFO` / `JOINED_GROUP` |
| **Metadata** | Inline `warm_cache_from_name!` (`JoinedGroup.GroupName.Name` / `GroupInfo.Name.Name`) + `schedule_metadata_fetch!` (Redis NX, 5 min). API warm força refresh de avatar |
| **Naming** | Contato só sobrescreve com nome `*(GROUP)`; nunca seed com pushName do membro (fallback = prefixo do JID) |
| **Automação** | `Custom::AutomationRuleListener` + `AutomationEventDispatcher` ignoram `source_id` `@g.us` |
| **Auto-assignment** | `Custom::Conversation#should_run_auto_assignment?` + `AssignmentService#assignable?` ignoram `@g.us` |
| **Sync contact** | Menu: grupo → `GroupMetadataFetchJob`; 1:1 → `ContactEnrichmentJob` (`force: true`) |
| **UI** | Bubble: `useGroupMessageSender` (`evolution_go_participant_push_name`, fallback dígitos do JID) |
| **Reuso** | `GroupContactService`, `GroupParticipantService`, `GroupMetadataService` (Go vs Node subject) |
| **Fixtures** | `message_inbound_group*.json`, `webhook_group_info.json`, `webhook_joined_group.json` |

---

## 10. Provider key separado

| Decisão | Valor |
|---------|-------|
| **Key** | `evolution_go` — **não** `evolution` |
| **Motivo** | Contratos REST, eventos e auth incompatíveis — ver [differences-from-evolution-api.md](./differences-from-evolution-api.md) |

---

## 11. Reuso de código Evolution API

| Decisão | Valor |
|---------|-------|
| **ApiClient** | Classe nova `EvolutionGo::ApiClient` |
| **Normalizer** | Classe nova — mapear `MESSAGE` não `MESSAGES_UPSERT` |
| **Infra Fase 0** | Compartilhar registry + prepends |
| **Wizard Vue** | Componente `EvolutionGo.vue` + composables dedicados (`useEvolutionGoQrSession`, health, import) — `useGatewayWhatsappWizard` compartilhado **não** foi extraído; ver [frontend-wizard-spec.md](./frontend-wizard-spec.md) e [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) |

---

## 12. Mutex e batch no job

Evolution Go envia **um evento por POST** (não batch `data[]` como Evolution API em alguns casos).

Prepend deve expor `contact_sender_id` compatível com payload **já normalizado**.

---

## 13. QR e ActionCable

| Decisão | Valor |
|---------|-------|
| **Canal** | `evolution_go:connection:{inbox_id}` |
| **Eventos** | `qrcode`, `connection` |
| **Fallback** | Polling `GET /instance/qr` + `GET /instance/status` a cada 3s |

---

## 14. Segredos no `provider_config`

| Campo | Tratamento |
|-------|------------|
| `global_api_key` | Write-only; GET masked |
| `instance_token` | Write-only; GET masked |
| `webhook_token` | Gerado no create; nunca expor em logs |
| `proxy_password` | Write-only |

---

## 15. Licença Evolution Go

| Decisão | Valor |
|---------|-------|
| **Escopo fork** | Documentar pré-requisito; operador ativa licença no servidor Go |
| **Código Chatwoot** | Não implementar fluxo de licença — fora do escopo |

---

## 16. Defaults das regras (fork)

| Campo | Default |
|-------|---------|
| `sign_msg` | `false` |
| `ignore_groups` | `true` |
| Reabrir conversa | `inbox.lock_to_single_conversation: true` |
| `merge_brazil_contacts` | `true` |
| `send_templates_as_text` | `true` |

Detalhe: [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## 17. Inbound `source_id`

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `data.key.id` no webhook `MESSAGE` |
| **Outbound (envio)** | `data.Info.ID` — ver §6 |
| **Validação** | Confirmar ambos no E2E — são campos distintos |

---

## 18. Evento inbound canônico

| Decisão | Valor |
|---------|-------|
| **Evento** | `MESSAGE` (wire: `Message`; normalized via `EventNames`) |
| **Echo** | `SEND_MESSAGE` subscrito; processado quando `ignore_from_me_echo: false` |

---

## 19. Webhook no connect

| Decisão | Valor |
|---------|-------|
| **Config** | `webhookUrl` + `subscribe` no body de `POST /instance/connect` |
| **Persistir** | Array `subscribe` em `provider_config` para reconnect |

---

## 20. Status API — casing

| Decisão | Valor |
|---------|-------|
| **OpenAPI** | `Connected`, `LoggedIn`, `Name` (PascalCase) |
| **Implementação** | `ApiClient` aceita PascalCase e camelCase até E2E |

---

## 21. Wizard — proxy via backend

| Decisão | Valor |
|---------|-------|
| **Chamadas REST Go** | Sempre via **backend Chatwoot** (`ConnectionService`) — nunca `global_api_key` no browser |
| **Endpoints internos** | Ver [frontend-wizard-spec.md § API](./frontend-wizard-spec.md#api-dashboard-contrato) |
| **Motivo** | Segurança keys + CORS + licença Go no servidor |
| **Status** | **✅ Fechado** (jun/2026) |

---

## 22. Persistência `global_api_key`

| Decisão | Valor |
|---------|-------|
| **Persistir no channel** | **Sim** — write-only masked em `provider_config` |
| **Uso** | `DELETE /instance/delete/{id}`, `GET /instance/all`, reconnect admin |
| **Modo "instância existente"** | `global_api_key` opcional no wizard — obrigatório só para delete/list admin |
| **Alternativa rejeitada** | Só env vars servidor CW — quebra multi-tenant |

**Status:** **✅ Fechado** (jun/2026)

---

## 23. Reconnect e webhook

| Decisão | Valor |
|---------|-------|
| **Reconnect** | `POST /instance/connect` com `webhookUrl` + `subscribe` **sempre reenviados** |
| **Fonte** | `provider_config.webhook_token`, `instance_name`, array `subscribe` persistido |
| **Motivo** | Evolution Go não tem `POST /webhook/set` — connect é o único ponto de configuração |

`ConnectionService#reconnect!` deve montar URL: `#{FRONTEND_URL}/webhooks/evolution_go/#{name}?token=#{secret}`.

Detalhe operação: [troubleshooting.md § Reconnect](./troubleshooting.md).

---

## 24. `POST /instance/reconnect` vs connect

| Decisão | Valor |
|---------|-------|
| **Caminho canônico fork** | `POST /instance/connect` com `webhookUrl` + `subscribe` — ver §23 |
| **`POST /instance/reconnect`** | Existe no Postman; **não usar** no fork — não garante reconfiguração de webhook |
| **`ConnectionService#reconnect!`** | `disconnect` (opcional) → `connect` com URL + subscribe persistidos |
| **Spike** | Validar se `reconnect` preserva webhook; se sim, documentar como atalho ops — não substituir connect no código |

**Status:** **✅ Fechado** (22/jun/2026) — connect é único ponto de configuração webhook.

---

## 25. Download mídia inbound (Fase 2)

| Decisão | Valor |
|---------|-------|
| **Endpoint** | `POST /message/downloadmedia` only (body `{ message }`) |
| **`ApiClient`** | `download_media` — no `/message/downloadimage` fallback (absent from current swagger) |
| **Job queue** | `MediaDownloadJob` on `:default` |
| **Resposta Go** | `data.base64` = **data URL completa** (`data:<mime>;base64,...`) via `dataurl.String()` — **não** base64 puro |
| **Decode Chatwoot** | `MediaDecoder` deve strip do prefixo `data:...;base64,` antes de `Base64.decode64` |

**Bug jul/2026:** sem strip, blobs Active Storage ficam corrompidos (magic `75ab5a6a…`); PDF viewer mostra "Falha ao carregar documento PDF". Afeta documento, imagem, áudio, etc.

**Status:** **✅ Atualizado** (09/jul/2026) — fix em `MediaDecoder#strip_data_url_prefix`.

---

## 26. Normalização de casing — `ApiClient`

| Decisão | Valor |
|---------|-------|
| **Problema** | Evolution Go mistura PascalCase (whatsmeow `Info.ID`) e camelCase (REST `connected`) |
| **Helper** | `dig_field(hash, *keys)` — tenta variantes `key`, `Key`, camelize, Pascalize |
| **Uso** | `connection_status`, `advanced-settings` GET/PUT, `sync_phone_number!` |
| **PUT body** | Serializar com chaves do OpenAPI create (`rejectCall`, `ignoreGroups`); aceitar leitura Postman (`rejectCalls`) no GET |

Ver implementação sugerida em [spec-design.md § ApiClient](./spec-design.md).

**Status:** **✅ Fechado** (22/jun/2026)

---

## 27. Prepend collision — envelope Go vs Node

| Decisão | Valor |
|---------|-------|
| **Problema** | O prepend evolution Node detecta `evolution_envelope?` verificando `params[:event].present? && params[:instance_name ou :instance].present?`. Evolution Go usa o mesmo formato de envelope — sem isolamento, o prepend Node intercepta eventos Go e retorna `return` (não `super`), descartando-os silenciosamente |
| **Solução** | `EvolutionGoController#sanitized_job_payload` injeta `:evolution_go_instance_name` em vez de `:instance_name` e **remove** o campo `instance` do raw payload antes de enfileirar |
| **Detecção Go** | `evolution_go_envelope?(params)` usa `params[:evolution_go_instance_name].present?` — único e não ambíguo |
| **Status** | **✅ Fechado** (24/jun/2026) |

```ruby
# EvolutionGoController
def sanitized_job_payload
  raw = params.to_unsafe_hash.except('controller', 'action', 'instance_name', 'token')
  raw.delete('instance')   # remove campo ambíguo do envelope bruto
  raw
end

def process_payload
  Webhooks::WhatsappEventsJob.perform_later(
    sanitized_job_payload.merge(
      evolution_go_instance_name: params[:instance_name],
      channel_id: @channel.id
    )
  )
  head :ok
end
```

**Também necessário:** atualizar o prepend evolution Node para usar `return super(params)` (não `return`) no guard de canal não encontrado — evita descarte silencioso em caso de envelope desconhecido futuro.

---

## Histórico

| Data | Decisão |
|------|---------|
| jun/2026 | Levantamento completo; provider `evolution_go` separado; webhook auth por query token |
| jun/2026 | ADR §22 `global_api_key` fechado; §23 reconnect sempre reenvia webhook no connect |
| 22/jun/2026 | Audit Postman MCP; §24 reconnect vs connect; §25 download mídia; §26 casing ApiClient |
| 24/jun/2026 | ADR §27 prepend collision; fix EvolutionGoController envelope key; registry format |
| jul/2026 | §28–§31: echo sync, EventNames, latency, SSRF guard; §7/§18/§25 updated |
| 13/jul/2026 | §32: avatar backoff + quote participant com phone placeholder |
| 2/ago/2026 | §9 Grupos expandido: GroupInfo/JoinedGroup, schedule dedup, naming, automação/auto-assign, Sync contact branch |
| 16/jul/2026 | §33: message reactions chip + context menu |
| 16/jul/2026 | §33 addendum: `user:self`, timeout 15s, optimistic UI, Node parity, cleanup rake |
| 16/jul/2026 | §34: pseudo-forward de mensagem no Chatwoot (sem API Go) |
| 17/jul/2026 | §35: message edit — UI CW + anti-loop + plaintext protocol; addendum delete/enrichment 17/jul pm |
| 18/jul/2026 | §33 addendum: ChatJid prefere `@lid`; menu Reações expansível; optimistic `findStoreMessage` |
| 18/jul/2026 | Meta AI `richResponseMessage` + unwrap `botInvokeMessage` |
| 18/jul/2026 | §36 addendum: avatar `/user/avatar` LID-first; timeout → cooldown 30m (`avatar_timeout_at`), não 6h |

---

## 28. Phone echo sync (`SEND_MESSAGE`)

| Decisão | Valor |
|---------|-------|
| **Service** | `PhoneOutgoingSyncService` + `PeerContactInboxResolver` |
| **Setting** | `ignore_from_me_echo` (default `true`) |
| **Dedup** | `source_id` + `MessageDedupLock`; release lock on early exit |

---

## 29. Event name normalization

| Decisão | Valor |
|---------|-------|
| **Module** | `Custom::Whatsapp::EvolutionGo::EventNames` |
| **Wire** | PascalCase (`Message`, `LoggedOut`) → SCREAMING_SNAKE (`MESSAGE`, `LOGGED_OUT`) |
| **Handlers** | Accept aliases: `LOGGEDOUT`, `QR_CODE`, `DELETE`, `RECEIPT`, etc. |

---

## 30. Latency & queue priority (jul/2026)

| Decisão | Valor |
|---------|-------|
| **Webhook enqueue** | `WhatsappEventsJob` on queue `:default` |
| **`last_webhook_at`** | Debounced 30s via Redis `EVOLUTION_GO_WEBHOOK_TOUCH_DEBOUNCE` |
| **Media / mark-read** | `MediaDownloadJob`, `MarkReadJob` on `:default`; `mark_read_on_reply` async |
| **ApiClient** | `RETRY_BACKOFF` 0.1s; `validate_provider_config` cache 60s |
| **Runtime config** | `ProviderConfigMerger` atomic JSONB merge |

---

## 31. SSRF guard — server check

| Decisão | Valor |
|---------|-------|
| **Module** | `Custom::Whatsapp::EvolutionGo::UrlSafetyGuard` |
| **Blocks** | Link-local / cloud metadata (`169.254.0.0/16`, etc.) |
| **Allows** | RFC1918, localhost (self-hosted setups) |
| **ApiClient** | `follow_redirects: false` on all requests |

---

## 32. Avatar enrichment backoff & quote participant (13/jul/2026)

| Decisão | Valor |
|---------|-------|
| **Avatar timeout** | `ApiClient::AVATAR_REQUEST_TIMEOUT` = 12s; `/user/avatar` **e** `/user/info` em `NON_RETRYABLE_PATHS` |
| **Backoff key** | `evolution_go_avatar_attempted_at` em `contact.additional_attributes` |
| **Cooldown** | `ContactEnrichmentService::AVATAR_RETRY_COOLDOWN` = 6h (falta de avatar não reenfileira a cada inbound) |
| **Force refresh** | `force: true` / `POST evolution_go_refresh_contacts` ignora cooldown |
| **Quote own message** | `quoted.participant` = JID do negócio; se `phone_number` é `+55000…`, extrair dígitos de `instance_name` (`channel_business_phone`) |
| **Quote peer message** | Usar `evolution_go_remote_jid` do peer; não usar remote_jid de mensagens `fromMe` (é o chat peer, não o sender) |

---

## 33. Message reactions — chip + context menu (16/jul/2026)

| Decisão | Valor |
|---------|-------|
| **Inbound UX** | Não criar mensagem; atualizar `content_attributes.reactions` na mensagem alvo + chip na bolha (`Base.vue`) |
| **Outbound UX** | Context menu item “Reactions” / “Reações” → painel com set curto `👍 ❤️ 😂 😮 😢 🙏` + remove; `POST …/messages/:id/evolution_go_react` |
| **Store** | `Custom::Whatsapp::ReactionsStore` (`BUSINESS_ACTOR_KEY = user:self`) — shared Go + Node |
| **Services (Go)** | `MessageReactionPayloadExtractor`, `MessageReactionSyncService`, `ReactSyncService`, `ApiClient#react` |
| **Services (Node)** | Paridade em `Custom::Whatsapp::Evolution::*` + `ApiClient#send_reaction` → `/message/sendReaction/:instance` |
| **Chat JID** | `ChatJid.for_message` prioriza `@lid` (attrs / contact / `identifier`) antes de PN `@s.whatsapp.net` — peers LID-mode |
| **Ator negócio** | Sempre `from: user`, `actor_key: user:self` (inbound `fromMe` e outbound dashboard); `actor_id` só informativo no outbound |
| **Remove** | `reaction` vazio ou `"remove"`; texto vazio no webhook |
| **Missing target** | Go: `mutation_stats.inbound_reaction_skipped`; Node: log `inbound_reaction_skipped` |
| **Placeholder** | Removido `[Reaction message]`; rake `evolution_go:cleanup_reaction_placeholders` (dry_run default) |
| **Timeout Go** | `REACT_REQUEST_TIMEOUT = 15s`; `/message/react` em `NON_RETRYABLE_PATHS` ([evolution-go#28](https://github.com/evolution-foundation/evolution-go/issues/28)) |
| **Lista** | Inbound bump `conversation.last_activity_at` **sem** unread |
| **Chip UX** | Highlight ring se `user:self`; clique remove reação do negócio; optimistic UI no menu |
| **Escopo** | `evolution_go` + `evolution` (Node) |

### Addendum pós-MVP (16/jul/2026)

- Unificar ator evita duplicar chip quando o agente reage no dashboard após echo `fromMe` do celular.
- Optimistic UI: snapshot → update local → POST → merge ou rollback + alert.
- E2E: validar `/message/react` na versão Go do operador e anotar em `evolution-target-version.txt`.

### Addendum 18/jul/2026 — LID + menu UX

- `ChatJid` prioriza `@lid` antes de PN stale em `evolution_go_remote_jid` (react/delete/edit). PN errado podia retornar HTTP 200 no Go sem grudar a reação no WA.
- Optimistic update usa a mensagem completa da store (`findStoreMessage`) — payload do context menu sem `sender` fazia a bolha pular L→R.
- Menu: item padrão “Reactions”/`Reações` (ícone emoji) expande painel com o set curto; emojis como `div` (não `<button>`) para não disparar `@blur` do `ContextMenu`.
- E2E local Contas-Receber / Pedidos: `/message/react` OK com LID (~0,2–1s).

---

## 34. Pseudo-forward de mensagem no Chatwoot (16/jul/2026)

| Decisão | Valor |
|---------|-------|
| **Por quê Chatwoot-only** | Evolution Go não expõe `/message/forward` nem flag `ContextInfo.Forwarded` |
| **Comportamento** | Reenviar cópia (texto + anexos) via `POST …/messages` no destino → `SendReplyJob` |
| **UX** | Context menu → modal (preview, recentes mesmo inbox, busca contato, multi-select até 5) |
| **Escopo** | Inbox `evolution_go` / `evolution`; mesmo inbox da origem |
| **Badge** | `content_attributes.forwarded` + chip “Forwarded” no dashboard; **sem** rótulo nativo no WhatsApp |
| **Implementação** | `useMessageForward.js` + `MessageForwardModal.vue` em `custom/`; thin FORK no menu/`Message.vue`/`Base.vue` |
| **Docs feature** | [doc/feature/message-forward/](../../message-forward/) |

---

## 35. Message edit — inbound/outbound (17/jul/2026)

| Decisão | Valor |
|---------|-------|
| **API outbound** | `POST /message/edit` `{ chat, messageId, message }` — OpenAPI / `ApiClient#edit_message` (não `number`) |
| **Outbound CW → WA** | Opt-in `sync_edit_to_whatsapp` (default `false`) via `EditSyncService` + `EvolutionGoEditSync` em `after_update_commit` |
| **UI agente (17/jul)** | Context menu **Edit** quando `sync_edit_to_whatsapp` + outgoing + `source_id`; modal → `POST …/evolution_go_edit` → `MessageContentEditService` |
| **Inbound WA → CW** | `mark_inbound_edited` (default `true`) → `MessageEditSyncService`; sinais `IsEdit` / `messageType: "edit"` / type 14 / `typeName: MESSAGE_EDIT` |
| **ID original** | `protocolMessage.key.ID` (ou `secretEncryptedMessage.targetMessageKey.ID`) — **não** `Info.ID` |
| **Texto** | `editedMessage.conversation` ou `editedMessage.extendedTextMessage.text` (+ captions mídia) |
| **`Info.Edit`** | Só `"1"` / `true` = edit; revoke usa `"7"` e **não** dispara path de edit |
| **Envelope criptografado** | `secretEncryptedMessage` sem plaintext → **skip** (`encrypted_edit`); stub incompleto → `nil`. Residual Go [#62](https://github.com/evolution-foundation/evolution-go/issues/62) / [#92](https://github.com/evolution-foundation/evolution-go/issues/92) |
| **Orphan** | Qualquer edit sem mensagem no CW → skip + `inbound_edit_skipped` (**não** inventa `#{id}-edited`) |
| **UX conteúdo** | `content_attributes.edited` / `edited_at` + badge “Edited”; **sem** prefixo no texto (legado ainda stripped) |
| **Outbound agente** | `MessageContentEditService` → `EditSyncService(raise_errors: true)` **antes** de persistir; falha WA → erro no modal, CW inalterado |
| **Anti-loop** | Skip outbound **sempre** que `edited_via_evolution_go_webhook` estiver true; skip também se `@evolution_go_edit_synced_inline` |

**Addendum 17/jul/2026:** guard reforçado em `EvolutionGoEditSync` + UI edit (`MessageEditModal`, `useMessageEdit`, rota `evolution_go_edit`).

**Addendum (review):** agentes não recebem `provider_config` (segredos). Flags `sync_edit_to_whatsapp` / `sync_delete_to_whatsapp` expostas no JSON do inbox (top-level) para gateway providers — sem isso o menu Edit só aparecia para admin.

**Addendum (melhorias):** soft-fail removido no path do agente (sync WA first); prefixo legado removido do storage; caption de mídia editável quando `content` presente.

**Addendum (17/jul pm — alinhamento contrato Go):** `Info.Edit` restrito; revoke signals (`IsRevoke` / `messageType`); job consome revoke mesmo com `mark_inbound_deleted: false`; `DeleteSyncService` reverte soft-delete se API falhar; fixtures `message_edit.json` / `message_edit_api_echo.json` / `message_revoke.json` atualizadas.

---

## 36. Contact enrichment / refresh (17/jul/2026)

| Decisão | Valor |
|---------|-------|
| **Query `/user/info`** | Preferir `@lid` → JID store → **dígitos plain** (evitar `phone@s.whatsapp.net` BR com 9º dígito que devolve Users vazios) |
| **Avatar** | Preferir `PictureURL` do `/user/info`; skip re-download se `PictureID` igual e avatar attached; `/user/avatar` ainda aceita URL ou base64 |
| **Rate-limit** | 429 / `rate-overlimit` → short-circuit; **não** marcar `enriched_at` / cooldown avatar longo; `/user/info` e `/user/avatar` em `NON_RETRYABLE_PATHS` |
| **Refresh bulk** | `ContactsRefreshService`: stagger `ENQUEUE_SPACING = 3s` + lock TTL dinâmico |
| **Import abort** | Toggles off mid-run → `Import::Runtime#abort_disabled_import!` → `import_status: idle` |

**Addendum 18/jul/2026 — avatar LID + timeout:**

| Decisão | Valor |
|---------|-------|
| **Query `/user/avatar`** | Mesma prioridade do info: `@lid` → PN `@s.whatsapp.net` → dígitos do JID; **um** fallback se a 1ª falhar |
| **Timeout de rede** | `Net::ReadTimeout` / `OpenTimeout` → **não** gravar `evolution_go_avatar_attempted_at` (6h); grava `evolution_go_avatar_timeout_at` com backoff **30 min** |
| **Cooldown deferred** | `finalize_avatar_miss!` só após esgotar candidatos (evita 6h prematuro se LID vazio e PN ainda pode responder) |
| **Cooldown 6h** | Apenas ausência de foto / privacidade (HTTP sem URL/base64), não falha transitória da Go |
| **Relatório prod** | [avatar-failures-report.md](./avatar-failures-report.md) (account 12) |
