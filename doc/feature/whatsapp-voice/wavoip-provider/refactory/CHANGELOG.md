# Changelog de refatoração — Wavoip

Resumo condensado de todo o trabalho de correção/qualidade já concluído na implementação
Wavoip. Para o texto completo (descrição, código antes/depois, racional) de cada item, veja
[archive/](./archive/) — mantido só como referência histórica.

## 13 jul. 2026 — ringback outbound Wavoip

| ID | Título | Status |
|----|--------|--------|
| UX-RINGBACK-01 | Sem som enquanto outbound “Ligando…” | ✅ `unlock` mudo no clique; `start` audível após `addCall` / widget |
| UX-RINGBACK-02 | Autoplay bloqueado após `await connectForInbox` | ✅ `unlock` síncrono nos botões **antes** do warm-up |
| UX-RINGBACK-03 | Outbound usava o mesmo `ringtone.mp3` do inbound | ✅ tom dedicado `public/audio/dashboard/ringback.mp3` |
| UX-RINGBACK-04 | Bell “silenciar toque” também mutava outbound | ✅ preferência vale **só inbound**; outbound sempre toca |
| UX-CHANNELS-01 | Toast com código `SIMULTANEOUS_LIMIT` | ✅ mapeia para `CHANNELS_FULL` (linhas ocupadas) |
| UX-CALLBACK-01 | “Ligar de volta” na bolha missed | ✅ loading Wavoip, telefone camel/snake, preflight antes do unlock |

Arquivos: `ringback.mp3`, `wavoipOutboundRingback.js`, `wavoipSdkResult.js`, botões Wavoip, `VoiceCall.vue` (callback), `FloatingCallWidget.vue` (`// FORK:`), i18n `CHANNELS_FULL`.

## 13 jul. 2026 — checklist token + docs ops

| ID | Título | Status |
|----|--------|--------|
| BUG-CHECKLIST-01 | Semáforo “Token” ⚠️ mesmo com token OK | ✅ usa `wavoip_device_token_configured` |
| DOC | Runbook checklist Vue + `STATUS_STALE` por token criptografado sem chaves | ✅ |

## 13 jul. 2026 — GAP-02 / GAP-04 + accept recorder

| ID | Título | Status |
|----|--------|--------|
| GAP-02 | Attribution só no PATCH do browser | ✅ `POST …/join` já persiste `accepted_by_agent_id` + broadcast; webhook fallback também em `completed` |
| GAP-04 | `PhoneNormalizer` LATAM local | ✅ retry Phonelib com dígitos + country hint; specs AR/MX/CO |
| BUG-ACCEPT-ID | Flush attribution falhava quando só `wavoipOfferId` batia | ✅ `findDbCallId` resolve `callSid` **ou** `wavoipOfferId` |

## 13 jul. 2026 — SDK 2.6.3 + painel device + accept WS

| ID | Título | Status |
|----|--------|--------|
| SDK | Bump `@wavoip/wavoip-api` `2.6.1` → `2.6.3` | ✅ tipos iguais; FE trata `status` `DISCONNECTED` |
| BUG-WS-01/02 | Accept com WebSocket morto | ✅ reconnect + toast + card retry |
| BUG-PANEL-01 | Wake/Reconnect/Restart com comportamento errado | ✅ matriz: Wake só hibernating; Reconnect soft QR+SDK; Restart HTTP |
| DOC | Runbook + sdk-reference matriz de botões; F1; architecture | ✅ |

Ver [operations-runbook.md](../operations-runbook.md#botões-do-painel-de-dispositivo-settings--chamadas) · [sdk-reference.md](../sdk-reference.md).

## 13 jul. 2026 — accept com WebSocket `disconnected`

**Sintoma:** banner `DEVICE_DISCONNECTED` + spinner ao atender; card existia via cable sem offer SDK.

| ID | Título | Severidade | Status |
|----|--------|------------|--------|
| BUG-WS-01 | Accept reusava client com WS morto | Alta | ✅ force reconnect em `connectForInbox` |
| BUG-WS-02 | Toast genérico / card sumia no fail | Média | ✅ `i18nKey` + card permanece para retry |
| IMP-WS-01 | Token rotacionado mascarado pelo bootstrap cache 15s | Média | ✅ `bypassCache` ao revalidar client conectado |

Arquivos: `useWavoipConnection.js`, `useWavoipCallSession.js`, `useCallSession.js`, `voiceSessionRegistry.js`, i18n `ACCEPT_OFFER_TIMEOUT` / `ACCEPT_FAILED`.

Ver [operations-runbook.md](../operations-runbook.md#atender-falha--banner-websocket--spinner-13-jul-2026) · [frontend-integration.md §4](../frontend-integration.md#4-lifecycle-por-agente).

## 26 jun. – 03 jul. 2026 — revisão inicial (32/32 concluído)

Revisão de código cobrindo toda a implementação `custom/**/wavoip/**` das fases 1–4.
Suite de regressão: 267 RSpec (voice scope) + ~165 Vitest.

| ID | Título | Severidade | Status |
|----|--------|------------|--------|
| BUG-01 | Deadlock em `acceptIncomingCall` (offer removida antes de chegar) | Alta | ✅ |
| BUG-02 | Alertas de chamada hardcoded em inglês | Média | ✅ |
| BUG-03 | Múltiplos `EscalateRingJob` por retransmissão de webhook | Média | ✅ |
| BUG-04 | `isConnecting` falso prematuro em conexões concorrentes | Baixa | ✅ |
| BUG-05 | `activeInboxId` não limpo ao cancelar outbound | Baixa | ✅ |
| BUG-06 | Botão "Acordar dispositivo" não chamava `device.wakeUp()` | Média | ✅ |
| GAP-OUTBOUND-01 | Widget outbound sumia com SDK ainda tocando | Alta | ✅ |
| GAP-01 | `offline_fallback: 'none'` não bloqueava escalação | Alta | ✅ |
| GAP-02 | `accepted_by_agent_id` sem retry | Alta | ✅ join persiste attribution; alerta UI; fallback webhook |
| GAP-03 | Token rotacionado não reconectava SDK | Média | ✅ |
| GAP-04 | `PhoneNormalizer` assume Brasil | Média | ✅ Phonelib + LATAM local + specs |
| GAP-05 | `ring_timeout_seconds` sem limite máximo | Baixa | ✅ |
| GAP-06 | Listener `statusChanged` podia vazar | Baixa | ✅ |
| GAP-07 | `assignee` ≡ `assignee_or_inbox_members` | Baixa | ✅ |
| GAP-08 | `notify_busy_agents` não valia na escalação | Baixa | ✅ |
| GAP-09 | Toggle admins sem contrato no backend | Baixa | ✅ |
| GAP-10 | `saveCallRouting` com race last-write-wins | Baixa | ✅ |
| GAP-11 | Polling mesmo com device já conectado | Baixa | ✅ |
| GAP-ADMIN | Admins online não recebiam toque inicial | Alta | ✅ |
| QC-01 a QC-14 | Duplicações, N+1, memory leaks, código morto (ver [archive/code-quality.md](./archive/code-quality.md)) | Média/Baixa | ✅ |

## 04 jul. 2026 — incidentes de produção corrigidos no dia

Encontrados e corrigidos na mesma sessão a partir de testes reais em produção (não fazem
parte da revisão de 26 jun.):

| Problema | Causa | Correção |
|----------|-------|----------|
| Notificação de "chamada recebida" disparando quando o **agente** iniciava uma ligação | SDK emite `offer` também para chamadas outbound; código tratava todo `offer` como inbound | `wavoipOutboundGuard.js` — ignora offer/cable quando o agente é quem iniciou |
| Conversa não reabria como `pending` ao receber ligação | `ConversationReopenService` só reabria como `open`; sem status dedicado para inbound | `status:` parametrizado (`pending` inbound / `open` outbound) + `wavoipInboundConversation.js` |
| Widgets fantasma de chamadas antigas em `ringing` reaparecendo | Nenhuma rede de segurança fechava calls presas quando o webhook de término nunca chegava | `Wavoip::Calls::StaleCallTimeoutScheduler` + `Wavoip::AutoNoAnswerRingJob` (backend) e `isStaleWavoipRingingMessage` (frontend, filtro de 3 min) |
| Gravação nunca aparecia no histórico | Conta não tinha o webhook `RECORD` habilitado no painel Wavoip | `Wavoip::Calls::DirectRecordingUrl` + `Wavoip::FetchDirectRecordingJob` — fallback via URL direta documentada (`storage.wavoip.com/{id}`) |
| "Ligar de volta" falhava com mensagem genérica | Sem checagem de dispositivo restrito/lotado; erro de conexão sem tradução | `wavoipOutboundPreflight.js` (checagem compartilhada com o botão do painel de contato) + mensagem `CONNECT_FAILED` |
| Webhook da Wavoip parou de entregar eventos silenciosamente | 502 transitório durante deploy — Wavoip não retentou nem voltou sozinho | Ver [operations-runbook.md#webhook-parou-de-chegar-sem-aviso-incidente-04-jul-2026](../operations-runbook.md#webhook-parou-de-chegar-sem-aviso-incidente-04-jul-2026) — reativação manual no painel Wavoip; código hardened 08 jul. 2026 |

## 04 jul. 2026 — segunda rodada (auditoria de confiabilidade)

Ver commits/specs do dia para detalhes. Resumo: lock atômico em schedulers, `CallFinalizer`
extraído para eliminar duplicação de "finalizar chamada" em 4 lugares, `DirectionInferrer`
extraído do `PayloadNormalizer`, correções de memory leak e reconciliação de IDs no frontend.
Detalhes completos no PR/diff correspondente.

## 06 jul. 2026 — dismiss / cable ended

| Problema | Correção |
|----------|----------|
| Mic permanecia aberto após `voice_call.ended` | `voiceCallCableRegistry.js` — `endSdkActiveCall(data.call_id)` antes de limpar store |
| Segunda aba do mesmo agente continuava tocando após outro aceitar | `voiceCallCableRegistry.js` — dismiss quando `!isWavoipSdkCallOwned` mesmo para mesmo user |

## 08 jul. 2026 — P0 hardening (Meta + Wavoip)

Correções de bloqueadores de produção e sync de documentação:

| Área | Correção |
|------|----------|
| Meta | `Voice::Provider::MetaCloud::Adapter` — channel injetado; `WhatsappCloudService` delega |
| Meta | `Whatsapp::Calls::StaleCallTimeoutScheduler` + jobs `ringing`/`in_progress` |
| Wavoip | `RecordHandler` — `enqueue_attachment` só quando `record_url` ainda não conhecido |
| Wavoip | `StaleCallTimeoutScheduler` estendido para `in_progress` |
| FE | QR `onBeforeUnmount`; `syncConnections` respeita call ativa; `isStaleWhatsappRingingMessage` |
| FE | `whatsappVoiceCableRegistry.js` — registry cable Meta (paridade com Wavoip) |
| Testes | 267 RSpec voice scope + ~165 Vitest (incl. `useWebRtcCallSession.spec.js`) |
| Ops | Checklist verificação webhook datado 2026-07-08 no runbook — live pendente acesso ops |

## 09 jul. 2026 — multiagente: parar notificação após accept + hardening

Bug reportado: após o primeiro agente aceitar, outros agentes continuavam vendo ring/push
porque a call permanece `ringing` até o webhook `ACTIVE`.

| ID | Título | Severidade | Status |
|----|--------|------------|--------|
| BUG-RING-01 | Escalação / push / cable re-notificavam após claim | Alta | ✅ |
| IMP-01 | `Wavoip::Calls::ClaimGuard` — `accepted_by_agent_id` (não cache-only) | — | ✅ |
| IMP-02 | `ClearIncomingNotificationsService` no `voice_call.accepted` / `ended` | — | ✅ |
| IMP-03 | FE: `markCallDismissed` + fechar OS Notification no dismiss / accept / reject | — | ✅ |
| IMP-04 | FE: consome `escalated: true` (não reabre widget dismissed/active) | — | ✅ |
| IMP-05 | `useCallSession` delega mais ao `voiceSessionRegistry` (helpers de provider) | — | ✅ |
| REV-01 | `POST /join` retorna 409 se outro agente já tem `JoiningAgentCache` | Alta | ✅ |
| REV-02 | `onAccepted` dismiss mesmo com `isCallJoining`; 2ª aba same-user sem toast | Média | ✅ |

**Comportamento esperado (doc M1):** primeiro `accept()` / PATCH → `voice_call.accepted` + clear
notificações in-app; EscalateRingJob e InboundPushService no-op se `ClaimGuard.claimed?`
(`accepted_by_agent_id`); outros agentes dismiss via cable/`acceptedElsewhere` e param de tocar.
`JoiningAgentCache` só evita double-join/accept (409), sem silenciar ring sozinho.

Validação browser E2E (2 agentes) permanece no checklist ops — ver [operations-runbook.md](../operations-runbook.md) G0.4 / M1.
