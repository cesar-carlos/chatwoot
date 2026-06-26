# Plano de refatoração — Wavoip

Fonte única de prioridade e ordem de execução para todas as correções e melhorias
identificadas na revisão de 26 jun. 2026.

**Total de itens:** 30 (5 bugs + 11 gaps + 14 qualidade)  
**Critério de pronto geral:** sem regressão nos testes existentes (76 RSpec + 21 Vitest)
+ spec específico para cada item corrigido.

---

## Mapa de prioridades

| ID | Documento | Título curto | Prioridade | Esforço | Fase |
|----|-----------|-------------|------------|---------|------|
| BUG-01 | [bugs.md](./bugs.md) | Deadlock em `acceptIncomingCall` | 🔴 Crítica | P | R1 |
| GAP-01 | [gaps.md](./gaps.md) | `none` não bloqueia escalação | 🔴 Crítica | P | R1 |
| GAP-02 | [gaps.md](./gaps.md) | `accepted_by_agent_id` sem retry | 🔴 Alta | M | R1 |
| BUG-02 | [bugs.md](./bugs.md) | Alertas hardcoded em inglês | 🟠 Alta | P | R1 |
| GAP-03 | [gaps.md](./gaps.md) | Token rotacionado não reconecta SDK | 🟠 Alta | M | R1 |
| BUG-03 | [bugs.md](./bugs.md) | Múltiplos `EscalateRingJob` por call | 🟠 Média | P | R2 |
| GAP-04 | [gaps.md](./gaps.md) | `PhoneNormalizer` assume Brasil | 🟠 Média | G | R2 |
| QC-01 | [code-quality.md](./code-quality.md) | `mark_webhook_verified!` duplicado | 🟡 Média | P | R2 |
| QC-02 | [code-quality.md](./code-quality.md) | `update_conversation` duplicado | 🟡 Média | P | R2 |
| QC-06 | [code-quality.md](./code-quality.md) | `assignee_scope` 2x SQL | 🟡 Média | P | R2 |
| QC-08 | [code-quality.md](./code-quality.md) | `ProcessWebhookJob` fila `:low` | 🟡 Média | P | R2 |
| GAP-07 | [gaps.md](./gaps.md) | `assignee` ≡ `assignee_or_inbox_members` | 🟡 Baixa | P | R3 |
| GAP-08 | [gaps.md](./gaps.md) | `notify_busy_agents` só no toque inicial | 🟡 Baixa | P | R3 |
| GAP-09 | [gaps.md](./gaps.md) | `administratorsToggle` sem contrato backend | 🟡 Baixa | P | R3 |
| GAP-10 | [gaps.md](./gaps.md) | `saveCallRouting` race last-write-wins | 🟡 Baixa | M | R3 |
| GAP-05 | [gaps.md](./gaps.md) | `ring_timeout_seconds` sem limite | 🟡 Baixa | P | R3 |
| GAP-06 | [gaps.md](./gaps.md) | Listener `statusChanged` vaza | 🟡 Baixa | P | R3 |
| GAP-11 | [gaps.md](./gaps.md) | Polling quando device já conectado | 🟡 Baixa | P | R3 |
| BUG-04 | [bugs.md](./bugs.md) | `isConnecting` false prematuro | 🟡 Baixa | P | R3 |
| BUG-05 | [bugs.md](./bugs.md) | `activeInboxId` não limpo no cancel | 🟡 Baixa | P | R3 |
| QC-03 | [code-quality.md](./code-quality.md) | `reload` redundante no `with_lock` | 🟢 Baixa | P | R3 |
| QC-04 | [code-quality.md](./code-quality.md) | String literal vs `INBOX_TYPES` | 🟢 Baixa | P | R3 |
| QC-05 | [code-quality.md](./code-quality.md) | Variável `normalized` morta | 🟢 Baixa | P | R3 |
| QC-07 | [code-quality.md](./code-quality.md) | `busy_agents` carrega Redis inteiro | 🟢 Baixa | M | R3 |
| QC-09 | [code-quality.md](./code-quality.md) | `DeviceStatusService` double reload | 🟢 Baixa | P | R3 |
| QC-10 | [code-quality.md](./code-quality.md) | `mediaByInbox` memory leak no disconnect | 🟢 Baixa | P | R3 |
| QC-11 | [code-quality.md](./code-quality.md) | `transition_allowed?` aceita terminal→terminal | 🟡 Baixa | P | R3 |
| QC-12 | [code-quality.md](./code-quality.md) | `webhook_url` silencia falta de `FRONTEND_URL` | 🟡 Baixa | P | R3 |
| QC-13 | [code-quality.md](./code-quality.md) | `onOutboundConnected` código morto | 🟢 Baixa | P | R3 |
| QC-14 | [code-quality.md](./code-quality.md) | `test_wavoip_webhook` bloqueia thread Puma | 🟡 Baixa | P | R3 |

**Esforço:** P = Pequeno (< 2h) · M = Médio (2–4h) · G = Grande (> 4h)

---

## Fase R1 — Corrigir antes do próximo deploy em produção

Bloqueadores funcionais e regressions de UX visíveis por usuário final.

### R1.1 — BUG-01: Deadlock no accept de chamada entrante

**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipIncomingOffer.js`

**O que fazer:**
- Em `removePendingOffer`, após `offerWaiters.delete(callId)`, chamar `waiter.reject(new Error('Offer cancelled'))`
- Adicionar spec Vitest: simula `waitForPendingOffer` + `removePendingOffer` concorrente, verifica que a promise rejeita (não pende)

**Critério de pronto:**
- [x] `removePendingOffer` rejeita a promise em espera
- [x] Spec `useWavoipIncomingOffer.spec.js` cobre o cenário concorrente
- [x] `acceptIncomingCall` trata o `reject` sem travar a UI

---

### R1.2 — GAP-01: `offline_fallback: 'none'` não bloqueia escalação

**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

**O que fazer:**
- `escalated_users` retorna `User.none` quando `offline_fallback == 'none'`
- `broadcast_escalated_ring` em `Broadcaster` já tem guard `return if streams.blank?` — funcionará automaticamente
- Adicionar spec RSpec: inbox com `offline_fallback: 'none'` + `ring_timeout_seconds: 60` → `escalated_pubsub_tokens` deve retornar `[]`

**Critério de pronto:**
- [x] `escalated_users` respeita `'none'`
- [x] Spec cobre: `none` → escalação vazia; qualquer outro fallback → escalação não vazia
- [x] Spec de integração: `EscalateRingJob` + `incoming_call_offline_fallback: 'none'` → nenhum broadcast

---

### R1.3 — GAP-02: `accepted_by_agent_id` sem retry

**Arquivo:** `custom/app/javascript/dashboard/lib/wavoip/wavoipAcceptRecorder.js`

**O que fazer:**
- Substituir re-enfileiramento silencioso por retry com backoff limitado (máx 3 tentativas, 1s/2s/4s)
- Após todas as tentativas falharem, emitir `console.warn` com callSid e dbCallId

**Critério de pronto:**
- [x] Retry até 3x com backoff exponencial
- [x] Falha final loga aviso (não silenciosa)
- [x] Spec: mock de `CallsAPI.recordAccept` falhando 2x e sucedendo na 3ª

---

### R1.4 — BUG-02: Alertas hardcoded em inglês

**Arquivos:**
- `custom/app/javascript/dashboard/lib/voice/voiceCallCableRegistry.js`
- `custom/app/javascript/dashboard/lib/wavoip/wavoipCallDiagnostics.js`

**O que fazer:**
- `voiceCallCableRegistry.js`: remover import do JSON de locale; passar `t` como parâmetro nos handlers ou usar `useI18n()` se o módulo puder ser convertido em composable
- `wavoipCallDiagnostics.js`: receber `translateFn` opcional como parâmetro de `wireCallDiagnostics`; chamadores passam `t` de seus contextos

**Critério de pronto:**
- [x] Nenhum import direto de `dashboard/i18n/locale/en/` em arquivos de runtime
- [x] Alertas exibem o idioma ativo do usuário

---

### R1.5 — GAP-03: Token rotacionado não reconecta SDK

**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipConnection.js`

**O que fazer:**
- Incluir hash do `device_token` no cálculo de `getWavoipSdkSyncKey` — assim qualquer mudança de token invalida a key e dispara `syncConnections`
- Em `syncConnections`, para inboxes em `connectedInboxIds`, verificar se o token do registry bate com o da inbox. Se divergir, desconectar e reconectar

**Critério de pronto:**
- [x] Mudança de `device_token` na prop da inbox força reconexão do SDK sem reload de página
- [x] Spec: simula inbox com token A conectado → token muda para B → `syncConnections` reconecta com B

---

## Fase R2 — Melhorias de confiabilidade (próximo sprint)

Itens que não travam o fluxo mas criam risco em produção sob carga ou em edge cases.

### R2.1 — BUG-03: Múltiplos `EscalateRingJob` por call

**Arquivo:** `custom/app/services/wavoip/calls/ring_escalation_scheduler.rb`

```ruby
def schedule
  timeout = inbox.channel.ring_timeout_seconds
  return unless timeout.positive?

  lock_key = "wavoip:escalate_lock:#{call.id}"
  return if Rails.cache.read(lock_key)

  Rails.cache.write(lock_key, true, expires_in: (timeout + 5).seconds)
  Wavoip::EscalateRingJob.set(wait: timeout.seconds).perform_later(call.id)
end
```

**Critério de pronto:**
- [x] Múltiplos INCOMING_RING para o mesmo call → exatamente 1 job agendado
- [x] Spec: 3 chamadas a `schedule` → `EscalateRingJob` enfileirado 1x

---

### R2.2 — GAP-04: `PhoneNormalizer` assume Brasil

**Arquivo:** `custom/app/services/wavoip/phone_normalizer.rb`

Avaliar uso de `Phonelib.parse(phone, country_hint)`. Se `phonelib` não cobrir os casos
de telefone sem `+` do Wavoip adequadamente, documentar o comportamento atual como
limitação explícita com um TODO rastreável.

**Critério de pronto:**
- [x] Número sem `+` chegando via inbox não-brasileiro não recebe prefixo `+55`
- [x] Spec: inbox BR + número US sem `+` → não prefixado com 55
- [x] Spec: inbox BR + número BR sem `+` (11 dígitos) → prefixado com 55

---

### R2.3 — QC-01 + QC-02: Duplicações `mark_webhook_verified!` e `update_conversation`

Consolidar em `Channel::Wavoip#mark_webhook_verified!` (com `with_lock`) e
`Call#sync_conversation_call_attributes!`.

**Critério de pronto:**
- [x] Nenhuma cópia duplicada nos serviços
- [x] Specs existentes passam sem alteração

---

### R2.4 — QC-06: `assignee_scope` 2x SQL

```ruby
def assignee_or_fallback(fallback_scope)
  scope = assignee_scope
  scope.exists? ? scope : fallback_scope
end
```

**Critério de pronto:**
- [x] 1 query SQL em vez de 2 para o caminho do assignee

---

### R2.5 — QC-08: `ProcessWebhookJob` na fila `:low`

Mover para `:default`. Criar `Wavoip::ProcessRecordWebhookJob` (ou usar o já existente
`AttachRecordingJob`) para o processamento de `RECORD` na fila `:low`.

**Critério de pronto:**
- [x] Eventos `CALL` e `DEVICE` processados na fila `:default`
- [x] Eventos `RECORD` permanecem em fila de menor prioridade

---

## Fase R3 — Polimento e housekeeping

Itens de baixo risco, alta legibilidade e pequenas melhorias de UX.

| ID | Ação resumida |
|----|---------------|
| GAP-07 | Adicionar resolver `:assignee_only_scope` para opção `'assignee'` em `IncomingCallRecipients` |
| GAP-08 | `escalated_users` verificar `notify_busy_agents` antes de `broad_fallback_scope` |
| GAP-09 | Frontend forçar `include_admins: false` ao salvar `offline_fallback: 'none'` |
| GAP-10 | `saveCallRouting` fazer fetch do estado do servidor antes de salvar (evita race last-write-wins) |
| GAP-05 | Validação `ring_timeout_seconds <= 300` no model |
| GAP-06 | Guardar handler `statusChanged` e usar `device.off` como fallback em `waitForDeviceOpen` |
| GAP-11 | `onMounted` só chama `startPolling` se `!isConnected.value` |
| BUG-04 | Substituir `isConnecting` boolean por contador atômico |
| BUG-05 | `clearRingingOutgoingCall` limpa `activeInboxId` |
| QC-03 | Remover `call.reload` redundante dentro de `with_lock` |
| QC-04 | `INBOX_TYPES.WAVOIP` em vez de string literal em `useWavoipCallSession` |
| QC-05 | Renomear `normalized` para `log_payload` em `ProcessWebhookJob` |
| QC-07 | Filtrar `busy_agents` por inbox members antes de carregar Redis |
| QC-09 | Consolidar para 1 `channel.reload` em `DeviceStatusService`; adicionar log ao atualizar `phone_number` |
| QC-10 | Exportar `clearWavoipMediaForInbox` e chamar dentro de `disconnectWavoipInbox` |
| QC-11 | `transition_allowed?` bloquear transições entre status terminais diferentes |
| QC-12 | `webhook_url` retornar `nil` (e exibir aviso na UI) quando `FRONTEND_URL` não configurado |
| QC-13 | Remover `onOutboundConnected` no-op do `wavoipVoiceCableHandlers` |
| QC-14 | `test_wavoip_webhook` usar `perform_later` em vez de `perform_now` |

**Critério de pronto para R3:**
- [x] Rubocop passa nos paths Wavoip Ruby (`custom/app/services/wavoip/`, jobs, model, specs)
- [x] ESLint passa nos paths Wavoip custom JS (`npx eslint custom/.../wavoip`, `custom/.../voice`)
- [x] Specs existentes verdes (104 RSpec + 83 Vitest no escopo Wavoip custom)
- [x] Spec novo para cada item que alterou comportamento observável

---

## Ordem de execução recomendada

```
R1.1 (deadlock)
  → R1.2 (none + escalação)    ← par natural, mesmo arquivo
  → R1.4 (i18n)                ← quick win, sem dependência
  → R1.3 (attribution retry)   ← JS isolado
  → R1.5 (token rotation)      ← pode ser feito em paralelo com R1.3

R2.1 (idempotência escalação)
R2.3 (DRY backend)             ← pré-requisito para R2 mais seguro
  → R2.2 (phone normalizer)    ← risco maior, isolar em branch
R2.4 + R2.5                    ← sem dependências

R3 — batch único de PR pequenos por arquivo
```

---

## Rastreamento de progresso

| ID | Status | PR / Commit |
|----|--------|-------------|
| BUG-01 | ✅ Concluído | — |
| GAP-01 | ✅ Concluído | — |
| GAP-02 | ✅ Concluído | — |
| BUG-02 | ✅ Concluído | — |
| GAP-03 | ✅ Concluído | — |
| BUG-03 | ✅ Concluído | — |
| GAP-04 | ✅ Concluído | — |
| QC-01 | ✅ Concluído | — |
| QC-02 | ✅ Concluído | — |
| QC-06 | ✅ Concluído | — |
| QC-08 | ✅ Concluído | — |
| GAP-07 | ✅ Concluído | — |
| GAP-08 | ✅ Concluído | — |
| GAP-09 | ✅ Concluído | — |
| GAP-10 | ✅ Concluído | — |
| GAP-05 | ✅ Concluído | — |
| GAP-06 | ✅ Concluído | — |
| GAP-11 | ✅ Concluído | — |
| BUG-04 | ✅ Concluído | — |
| BUG-05 | ✅ Concluído | — |
| QC-03 | ✅ Concluído | — |
| QC-04 | ✅ Concluído | — |
| QC-05 | ✅ Concluído | — |
| QC-07 | ⚠️ Reaberto | Pré-filtro removido pelo GAP-ADMIN fix; otimização via `hmget` pendente |
| QC-09 | ✅ Concluído | — |
| QC-10 | ✅ Concluído | — |
| QC-11 | ✅ Concluído | — |
| QC-12 | ✅ Concluído | — |
| QC-13 | ✅ Concluído | — |
| QC-14 | ✅ Concluído | — |

### Correções identificadas em revisão pós-implementação (26 jun. 2026)

| ID | Descrição | Status |
|----|-----------|--------|
| BUG-POS-01 | `IncomingCallRecipients#users` retornava `InboxMember` em vez de `User` → `pluck(:pubsub_token)` lançava `PG::UndefinedColumn`; nenhum broadcast ActionCable chegava aos agentes online | ✅ Corrigido |
| GAP-ADMIN | Administradores online/busy não recebiam o toque inicial quando `include_administrators=true` — só apareciam no fallback offline; introduzido `recipients_base_scope` | ✅ Corrigido |
| BUG-QR-01 | `WavoipQrScanModal.cleanupSession` desconectava o SDK incondicionalmente, mesmo quando a sessão de QR nunca o usou — interrompia a conexão do `WavoipConnectionHost` | ✅ Corrigido |
| BUG-QR-02 | `startSession` marcava `qrRefreshError=true` quando status era `connecting` e QR ainda não estava pronto — estado de transição normal exibia mensagem de erro | ✅ Corrigido |
| BUG-QR-03 | `WavoipQrDisplay.showLoading` não cobria o estado `connecting` sem QR — tela ficava vazia em vez de exibir spinner de espera | ✅ Corrigido |
