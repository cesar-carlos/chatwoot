# Spike Wavoip — notes

## Status unificado (04 jul. 2026)

**Veredicto:** `go com restrições` — fases 0–4 + refactory R1–R3 code-complete.

| Área | Estado |
|------|--------|
| Pipeline webhook | ✅ OK — aceita `caller`/`receiver` (fix 26 jun.); inbound I2/O2 passam via `bin/wavoip-pilot-verify` |
| SDK outbound | ✅ RINGING → ACTIVE comprovado (headless + browser parcial) |
| **W1** (painel Wavoip) | ⚠️ Pendente — toggle CALL + linha CALL no histórico do painel em chamada live |
| **G0.4 / M1** (multiagente browser) | ❌ Pendente — `acceptedElsewhere` + `voice_call.accepted` |
| **O1 / D1 / F1** (browser E2E) | ❌ Pendente — outbound bidirecional, dismiss, accept fail |

**Bloqueadores piloto:** W1 live panel proof + G0.4 browser E2E — **não** contradição de código vs. vendor; pipeline pronto quando bytes chegam.

### Gate matrix piloto (04 jul. 2026)

| Gate | Descrição | Status |
|------|-----------|--------|
| **W1** | Webhook CALL no painel Wavoip em chamada live | ⚠️ _pending live panel_ |
| **O1** | Outbound browser bidirecional | ⚠️ _pending (browser)_ |
| **M1 / G0.4** | Multiagente — toast + `acceptedElsewhere` | ❌ _pending (browser)_ |
| **D1** | Dismiss ✕ inbound → SDK reject | ⚠️ _pending (browser)_ |
| **F1** | Accept falha / timeout | ⚠️ _pending (browser)_ |
| **I1 / I2** | Inbound peer + caller/receiver | ✅ Pass (automated + fixtures live) |
| **O2** | Outbound webhook caller/receiver | ✅ Pass (automated) |

---

> **Nota:** seções abaixo datadas **19 jun. 2026** são evidência histórica do spike. Onde conflitarem com o status unificado acima (ex.: "webhooks not received"), prevalece o bloco **04 jul. 2026** — pipeline corrigido; W1 live panel proof ainda pendente.

**Status (19 jun. — histórico):** `go com restrições` — device `open`; outbound **connected** (RINGING → ACTIVE → ended); live webhooks from Wavoip panel not received during spike window (operational/vendor at the time).

**Date:** 19 Jun 2026 (audit fixes 20 Jun 2026)

**Audit fixes applied (20 Jun 2026):** source_id normalization, scoped SDK teardown, server-side `inbound_calls_enabled`, `channel_wavoip` gate, webhook key rotation UI, ProcessWebhookJob warn logging. **Live Wavoip panel webhook delivery remains unverified** — operational/vendor blocker, not code.

**Device token (masked):** `...261e`

---

## Gate results (G0.1–G0.7) — histórico 19 jun. 2026 _(supersedido pelo status 04 jul. 2026 acima)_

| Gate | Result | Evidence |
|------|--------|----------|
| **G0.1 SDK** | ✅ Pass | `@wavoip/wavoip-api@2.6.1`; device `open` via `statusChanged`; `contact.phone` = `556697193168`. |
| **G0.2 IDs** | ⚠️ Partial | Live SDK ids captured (`4BD9D82E…`, `9E144343…`, prior `521F44B4…`). **No live CALL webhook** during any call window. Simulated curl with SDK id → Call + voice_call created; pipeline works when bytes arrive. |
| **G0.3 Webhook bruto** | ⚠️ Partial | Public `POST {FRONTEND_URL}/webhooks/wavoip/{key}` → **202** (curl). **Zero** nginx POSTs from Wavoip origins during live calls (21:03–21:05 UTC). |
| **G0.4 Multiagente** | ❌ Not tested | Two-agent `acceptedElsewhere` not exercised. |
| **G0.5 Lifecycle** | ✅ Pass | Device `open`; simulated CALL lifecycle `ringing → in_progress → completed` in DB (prior run). Live call SDK lifecycle RINGING → ACTIVE → ended confirmed. |
| **G0.6 Segurança** | ✅ Pass | Token not in serializers; webhook key lookup unchanged. |
| **G0.7 Histórico** | ✅ Pass (simulated) | Call id=1, voice_call msg id=412799; duplicate CREATE idempotent (prior). **No new Call from live webhooks.** |

---

## Final live E2E (19 Jun 2026 ~21:04 UTC)

**Environment:** production inbox **42**, account 2, webhook URL confirmed:

`https://chat.se7esistemassinop.com.br/webhooks/wavoip/mz5uFxCZ4tVZn94Nm5osnqCQ`

| Step | Result |
|------|--------|
| SDK connect | ✅ `statusChanged open` ~1s |
| SIMULTANEOUS_LIMIT cleanup | ✅ Cleared after prior crashed session; probe + wait loop |
| `startCall({ to: '+5566999050319' })` | ✅ CallOutgoing.id `4BD9D82ED4A57FECAEA66E5A77586E4F` |
| SDK status trail | ✅ RINGING (21:04:16) → ACTIVE (21:04:18) → ended (21:04:49) |
| `peerAccept` | ✅ `activeId` = same as CallOutgoing.id |
| Live CALL webhook (Sidekiq) | ❌ **0** `ProcessWebhookJob` during call window |
| Live webhook (nginx) | ❌ **0** POST to `/webhooks/wavoip/*` (non-curl) during 21:03–21:05 UTC |
| DB auto-create (live) | ❌ `calls_count` still 1 (simulated id `521F44B4…` only) |

### Live webhook counts (this run)

| Type | Live received | Notes |
|------|---------------|-------|
| **CALL** | **0** | No CREATE/UPDATE from Wavoip |
| **DEVICE** | **0** | All historical DEVICE jobs were curl (62.72.11.49) |
| **RECORD** | **0** | — |

### SDK call ids (G0.2)

| Attempt | CallOutgoing.id | SDK status | Live webhook? | DB match? |
|---------|-----------------|------------|---------------|-----------|
| Run 1 (crash) | `9E144343ECC89927D654CA29F15A26E3` | RINGING → ACTIVE (AudioWorklet crash) | ❌ | ❌ |
| Run 3 (final) | `4BD9D82ED4A57FECAEA66E5A77586E4F` | RINGING → ACTIVE → ended | ❌ | ❌ |
| Prior simulated | `521F44B42A5DD487693DEB5E65A24C43` | RINGING → ACTIVE (live SDK) | ❌ live; ✅ curl | ✅ id=1 |

**G0.2 verdict:** Cannot confirm live SDK ↔ `whatsapp_call_id` correlation — Wavoip never POSTed. Simulated E2E with matching id shape confirms pipeline.

### Nginx evidence (all time)

Every `POST /webhooks/wavoip/mz5uFxCZ4tVZn94Nm5osnqCQ` in `/var/log/nginx/chatwoot_access_443.log` has User-Agent `curl/8.5.0` from `62.72.11.49` (our spike tests). **No Wavoip-origin POST observed.**

---

## Wavoip panel checklist (user action)

Per [Wavoip Webhook docs](https://wavoip.gitbook.io/api/webhook-beta.md):

1. **app.wavoip.com → Devices →** select device `556697193168`
2. **Integrações → Webhook**
3. URL: `https://chat.se7esistemassinop.com.br/webhooks/wavoip/mz5uFxCZ4tVZn94Nm5osnqCQ`
4. **Enable** webhook toggle
5. **Select events:** CALL (required), DEVICE (recommended)
6. Save — first valid POST sets `webhook_verified_at` in inbox provider_config

---

## Environment setup (spike)

```bash
export WAVOIP_SPIKE_DEVICE_TOKEN="$(RAILS_ENV=production bundle exec rails runner 'puts Channel::Wavoip.joins(:inbox).find_by!(inboxes: { id: 42 }).device_token')"

export WAVOIP_SPIKE_TEST_NUMBER='+5566999050319'

# Prod: Account 2 (Se7e), inbox id=42
node tmp/wavoip-final-e2e.mjs
```

Spike scripts (gitignored): `tmp/wavoip-final-e2e.mjs`, `tmp/wavoip-outbound-g02.mjs`.

---

## Ops fixes (19 Jun 2026)

| Fix | Result |
|-----|--------|
| Headless `AudioWorkletNode` stub | ✅ Added to `wavoip-final-e2e.mjs` — survives ACTIVE / peerAccept |
| SIMULTANEOUS_LIMIT cleanup | ✅ Wait loop (15s × up to 6) before outbound |
| Spike false "disconnected" | ✅ `statusChanged` events (prior) |
| `ensureDeviceReady` race | ✅ Wait for `open` up to 30s (prior) |

---

## Decisões pós-spike

| Decisão | Escolha |
|---------|---------|
| Seguir para piloto | **go com restrições** |
| Correlação SDK/webhook | Pipeline ready; live bytes unproven |
| Bloqueador principal | **Wavoip panel not POSTing** — verify webhook enabled + CALL events selected on correct device |
| Restrições | Outbound audio path works in headless (stub); live webhook ingress unproven; G0.4 not tested |

---

## What worked live

- Outbound call to `+5566999050319` — callee answered (ACTIVE), full end-to-end SDK session
- Device `open`, contact phone, SIMULTANEOUS_LIMIT recovery
- Simulated CALL webhook full lifecycle in production DB (prior run)
- Public webhook endpoint returns 202

## What did not work / gaps

- **Wavoip panel did not POST** during live calls despite URL configuration claim
- No automatic Call / voice_call message without webhook bytes
- G0.2 live correlation still pending
- Browser bidirectional audio not validated (headless Node only)

## Bugs fixed (this run)

| Issue | Fix |
|-------|-----|
| Node crash on ACTIVE (`AudioWorkletNode`) | Stub in `tmp/wavoip-final-e2e.mjs` |
| SIMULTANEOUS_LIMIT after crash | Cleanup wait loop before outbound |
| `WavoipCallingPage` empty webhook URL | Reads `wavoip_webhook_url` / `wavoip_setup_pending` (+ camelCase fallbacks) |

---

## Recommended next steps

1. **Wavoip panel:** enable webhook + CALL events on device `556697193168`; confirm first non-curl POST in nginx (`grep webhooks/wavoip /var/log/nginx/chatwoot_access_443.log | grep -v curl`).
2. **Re-run** `node tmp/wavoip-final-e2e.mjs` — expect `ProcessWebhookJob` with `whatsapp_call_id` matching SDK `CallOutgoing.id`.
3. **Browser pilot** — validate bidirectional audio with agent dashboard.
4. **G0.4** — two agent browsers for `acceptedElsewhere`.

**Phase 4 code complete:** outbound connected live; **live Wavoip webhook delivery is the remaining pilot gate.**

### E2E roteiro — `+5566999050312` (Jun 2026)

**Inbox piloto (dev):** `WAVOIP_INBOX_ID=106` (`+5566999050312`). Verificação: `WAVOIP_INBOX_ID=106 WAVOIP_TEST_PEER_PHONE=+5566999050312 bin/wavoip-pilot-verify`.

Fixtures live: [call_create_incoming_live_caller_receiver.json](./fixtures/call_create_incoming_live_caller_receiver.json), [call_create_outcoming_live_caller_receiver.json](./fixtures/call_create_outcoming_live_caller_receiver.json).

| # | Cenário | Passos | Critério | Pass/Fail |
|---|---------|--------|----------|-----------|
| O1 | Outbound | Agent online → conversa → ligar | Widget permanece até `peerAccept` / `peerReject` / `unanswered` / hangup do agente; depois `peerAccept`, áudio bidirecional, bolha `voice_call`, webhook ACTIVE/ENDED | _pending (browser)_ |
| I1 | Inbound (peer) | Fechar app.wavoip.com → ligar de `+5566999050312` | Widget + SDK `offer` → Accept → `PATCH /calls/:id` | **Pass** webhook row (peer format) |
| I2 | Inbound (caller/receiver) | `bin/wavoip-pilot-verify` ou POST com payload live | `Call` ringing sem log `Skipped create` | **Pass** (automated) |
| O2 | Outbound webhook | POST OUTCOMING CALLING caller/receiver | `Call` outgoing ringing | **Pass** (automated) |
| M1 | Multi-agente | 2 agentes online | B recebe toast; widget some via `voice_call.accepted` + SDK `acceptedElsewhere` | _pending (browser)_ |
| D1 | Dismiss ✕ inbound | Agent dismiss sem aceitar | SDK `reject`; contato para de tocar | _pending (browser)_ |
| F1 | Accept falha | Timeout / erro no Accept | Widget some; sem ring preso | _pending (browser)_ |
| W1 | Webhook | Toggle ON no painel Wavoip + evento **CALL** | Settings **Webhook verified**; histórico Wavoip mostra linha **CALL** (não só DEVICE) | _pending live panel_ |

`bin/wavoip-pilot-verify`: checks in-process W1 + I1 (peer) + I2/O2 (caller/receiver). HTTP curl usa payload caller/receiver (expect 202).

### Conclusão implementação (Jun 2026)

Fases A–E do plano de conclusão aplicadas:

- P0: `startCall` unwrap, join fail dismiss, dismiss inbound → SDK reject
- Multiagente: `voice_call.accepted` no PATCH + inbound ACTIVE; `onAccepted` sem race
- Backend: logging seguro, RECORD retry, push só online agents
- Settings: `WavoipDevicePanel` reativo, test webhook, restart/logout, diagnostics completos

### Melhorias pós-MVP aplicadas (Jun 2026)

- `offer.accept()` unwrap `{ call, err }`
- Cable/SDK reconcile (`awaitingSdkOffer`, `waitForPendingOffer`)
- `connectionStatusChanged` vs WhatsApp `statusChanged`
- `WavoipDevicePanel` (QR, pairing, wakeUp, diagnostics)
- `useWavoipNotifications`, `useWavoipMedia`, RECORD retry job
- `IncomingCallRecipients` → online inbox members first; offline fallback configurável (Settings → Chamadas)

### Bug fixed (settings tab, Jun 2026)

`WavoipCallingPage.vue` now reads `wavoip_webhook_url` / `wavoip_setup_pending` with camelCase fallbacks (`wavoipWebhookUrl`, `wavoipSetupPending`). Settings → Chamadas shows the webhook URL for admins. Post-creation alert in `Wavoip.vue` remains the primary copy path during inbox setup.

### Legacy column

`users.wavoip_token` exists on the `users` table but is **not** used by the Wavoip channel — device credentials live in `channel_wavoip.device_token`.

Fixture (simulated, prior run): [fixtures/call_create_outbound_live_e2e.json](./fixtures/call_create_outbound_live_e2e.json)

### Escalação (`escalated: true`)

`broadcast_escalated_ring` envia `voice_call.incoming` com `escalated: true` no payload. O frontend
não consome esse flag; após dismiss local (`isCallDismissed`), re-rings de escalação são ignorados
no cable handler (`voiceCallCableRegistry.onIncoming`).

---

## Re-spike automatizado (Jun 2026)

```bash
# No host da aplicação
WAVOIP_INBOX_ID=42 bin/wavoip-pilot-verify
```

Registra: feature flags, webhook URL, `device_token` configurado, inbound toggle, contagem de calls, smoke HTTP 202/401, **simulated inbound CALL** com peer `+5566999050312` (`WAVOIP_TEST_PEER_PHONE`).

**Rotação `device_token`:** gerar novo token em app.wavoip.com → Settings inbox → salvar → recarregar dashboard.

