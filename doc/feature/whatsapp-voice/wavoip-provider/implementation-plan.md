# Plano de implementação — Wavoip (revisão jun/2026)

Fases concretas alinhadas à [sdk-reference.md](./sdk-reference.md), fork strategy (`custom/` + `# FORK:` mínimo) e happy-path MVP.

**Pré-requisitos:** [README.md](./README.md) · [architecture.md](./architecture.md) · [official-docs.md](./official-docs.md) · feature `channel_voice` na conta.

**Mudança principal vs plano anterior:** saúde do dispositivo (`open`, QR, `wakeUp`) deixa de ser Fase 4 — é **pré-requisito** de qualquer chamada (SDK). Webhook skeleton sobe na Fase 1 junto com o canal.

---

## Princípios de execução (fork)

| Regra | Aplicação Wavoip |
|-------|------------------|
| Código novo em `custom/` | Models, services, jobs, composables, controllers, Vue do canal |
| `prepend_mod_with` | `Call`, `InboxesController` — não editar EE diretamente |
| `# FORK:` mínimo | Tile, registry, helpers de provider — ver [inventário FORK](#inventário-fork) |
| Preferir dados a código | `channel_voice` + flag opcional `channel_wavoip` em `custom/config/features.yml` |
| Classes pequenas | Handlers por `type`/`action`; composables &lt; 200 linhas |
| Não tocar stack Meta | Zero mudança em `WhatsappCallsController`, `useWhatsappCallSession` |
| Reusar EE onde couber | `Voice::InboundCallBuilder` com `provider: :wavoip`, `Voice::CallMessageBuilder` |

---

## Fase 0 — Spike (validação)

**Objetivo:** provar áudio + webhook + comportamento multi-aba antes de modelar canal.

**Docs oficiais:** [official-docs.md § Fase 0](./official-docs.md#por-fase-de-implementação-chatwoot) · [Instalação](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/installation.md) · [Webhook Beta](https://wavoip.gitbook.io/api/wavoip-docs/webhook-beta.md)

| # | Tarefa | Done |
|---|--------|------|
| 0.1 | Dispositivo em [app.wavoip.com/devices](https://app.wavoip.com/devices) | Token + status `open` |
| 0.2 | HTML mínimo: `new Wavoip({ tokens })`, `on('offer')`, `startCall({ to, fromTokens })` | Áudio bidirecional |
| 0.3 | Observar ciclo `Device`: `connecting`→QR, `open`, `hibernating`→`wakeUp()` | Notas no runbook |
| 0.4 | Webhook ngrok → log payload `CALL` CREATE/UPDATE | JSON real capturado |
| 0.5 | 2 abas, mesmo token — `acceptedElsewhere` | Comportamento documentado |
| 0.6 | Registrar `type`: `official` vs `unofficial` + `connectivityIssue` se houver | Impacto UI anotado |
| 0.7 | Validar campo `type` duplicado no payload webhook (bug doc) | Regra do `PayloadNormalizer` |
| 0.8 | `rails runner`: `Voice::InboundCallBuilder.perform!(..., provider: :wavoip)` | Enum + bolha OK — ver [spike-notes.template.md](./spike-notes.template.md) |
| 0.9 | Copiar payloads reais para [fixtures/](./fixtures/) | Templates substituídos |

**Saída:** `spike-notes.md` (interno) + fixtures JSON — template em [spike-notes.template.md](./spike-notes.template.md).

**Duração:** 2–4 dias.

---

## Fase 1 — Fundação (canal + webhook + dispositivo)

**Objetivo:** inbox criável, webhook recebendo, painel de dispositivo funcional. **Sem chamadas ainda.**

**Docs oficiais:** [Dispositivo](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md) · [Vincule WhatsApp](https://wavoip.gitbook.io/api/vincule-um-whatsapp.md) · [Webhook config](https://wavoip.gitbook.io/api/wavoip-docs/webhook-beta.md)

### Infra fork (uma vez)

| Entrega | Arquivo |
|---------|---------|
| Alias Vite `customDashboard` | `vite.shared.ts` `# FORK:` → `custom/app/javascript/dashboard` |
| Autoload STI | `Channel::Wavoip` registrado (Rails autoload `custom/app/models`) |

### Backend

| Entrega | Arquivo |
|---------|---------|
| Migration `channel_wavoip` | `db/migrate/…_create_channel_wavoip.rb` |
| Model | `custom/app/models/channel/wavoip.rb` |
| `CreateValidator` | `custom/app/services/wavoip/channels/create_validator.rb` |
| `create_wavoip_channel` | `prepend_mod_with` em `Enterprise::Api::V1::Accounts::InboxesController` |
| Enum `wavoip` em `Call` | `custom/app/models/custom/call.rb` + `Call.prepend_mod_with('Custom::Call')` |
| Webhook route + controller fino | `custom/.../webhooks/wavoip_controller.rb` — ver [webhook-contract.md](./webhook-contract.md) |
| Rate limit webhook | `Rack::Attack` em `custom/` |
| Job + dispatcher (log/ack) | `process_webhook_job.rb`, `dispatcher.rb` |
| `PayloadNormalizer` | Parse defensivo; ignorar payloads inválidos |
| Policy | `custom/app/policies/channel/wavoip_policy.rb` |

Webhook Fase 1 pode apenas **logar + 200**; handlers completos na Fase 2.

### Frontend

| Entrega | Arquivo |
|---------|---------|
| Tile `wavoip` | `ChannelList.vue` `# FORK:` |
| Gate | `ChannelItem.vue` `# FORK:` — só `channel_voice` |
| Wizard | `custom/.../channels/Wavoip.vue` + subcomponentes ([inbox-setup.md](./inbox-setup.md)) |
| `createWavoipChannel` | `custom/.../channelActions.js` ou prepend store |
| Factory | `ChannelFactory.vue` `# FORK:` |
| Settings | `WavoipCallingPage.vue` + **`WavoipDevicePanel.vue`** + **`WavoipOnboardingChecklist.vue`** |
| Registry vazio | `wavoipClientRegistry.js` (stub) |

### `WavoipDevicePanel` (crítico — SDK Device)

Conectar SDK só nesta tela (settings) na Fase 1 para validar token:

| Status SDK | UI |
|------------|-----|
| `connecting` | QR via `qrCodeChanged` |
| `close` | CTA pareamento / `pairingCode(phone)` |
| `open` | Badge verde + `contactChanged` vs `phone_number` |
| `hibernating` | Botão `wakeUp()` |
| `WAITING_PAYMENT`, `EXTERNAL_INTEGRATION_ERROR` | Banner bloqueante |

Sem `open`, botão ligar fica desabilitado nas fases seguintes.

### `# FORK:` nesta fase

```javascript
// inbox.js
export const INBOX_TYPES = { ..., WAVOIP: 'Channel::Wavoip' };
export const VOICE_CALL_PROVIDERS = { ..., WAVOIP: 'wavoip' };
if (channelType === INBOX_TYPES.WAVOIP) return VOICE_CALL_PROVIDERS.WAVOIP;
```

```javascript
// ChannelItem.vue
if (key === 'wavoip') return props.enabledFeatures.channel_voice;
```

### Done Fase 1

- [ ] Tile + wizard + redirect agentes
- [ ] `webhook_secret` gerado; URL copiável
- [ ] Webhook retorna 200 e enfileira job
- [ ] Settings mostram status real do dispositivo (SDK)
- [ ] Admin vê se token/dispositivo está `open` antes de operar
- [ ] Checklist onboarding (semáforo 6 passos) — [operations-runbook.md](./operations-runbook.md)
- [ ] `device_token` mascarado na API list (`••••last4`); completo só em edit/admin

**Duração:** ~1–1,5 semana.

---

## Fase 2 — Outbound (fatia vertical)

**Objetivo:** ligar da conversa com histórico CRM. Depende de dispositivo `open`.

**Docs oficiais:** [Outgoing](https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md) · [Active](https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md) · [Mídia](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md)

### Backend (handlers completos)

| Classe | Entrega |
|--------|---------|
| `CallHandler` + `CallCreateHandler` + `CallUpdateHandler` | Path outbound |
| `StatusMapper.from_webhook` | Só vocabulário webhook — [sdk-reference §7.1](./sdk-reference.md#71-webhook-callstatus--callstatus-rails) |
| `CallUpsertService` | `find_or_create` idempotente por `provider_call_id` |
| `CallUpdateHandler` | Ignora `UPDATE` que regride status terminal — [webhook-contract §3](./webhook-contract.md#3-idempotência) |
| `MessageSyncService` | Bolha `voice_call` outbound |
| `ConversationLinker` | Contato por `peer.phone` |

Chamar `Voice::InboundCallBuilder.perform!(..., provider: :wavoip)` no CREATE inbound ring — **não** duplicar builder.

### Frontend

| Classe | Entrega |
|--------|---------|
| `lib/voice/browserVoiceProviders.js` | `isBrowserVoiceProvider()` — reduz FORK em Vue |
| `lib/voice/voiceCallCableRegistry.js` | Handlers ActionCable por provider |
| `useWavoipConnection.js` | Conecta quando agente **online** no inbox |
| `lib/wavoip/callStatusUI.js` | Map SDK `CallStatus` → widget — [§7.2](./sdk-reference.md#72-sdk-callstatus--ui-browser) |
| `useWavoipOutboundCall.js` | `startCall({ to, fromTokens })` + `wakeUp` se `hibernating` |
| `useWavoipActiveCall.js` | `mute`/`end`, `connectionStatus`, `connectivityIssue` toast |
| `useWavoipCallSession.js` | Facade fina |
| `useCallSession.js` | `# FORK:` registry `BROWSER_VOICE_HANDLERS` |
| `ConversationCallButton.vue` | Habilitar `wavoip` |
| `calls.js` | `# FORK:` `teardownByProvider` case `wavoip` |

### Gates runtime (SDK)

Antes de `startCall`:

1. `Device.status === 'open'` (senão toast + link settings)
2. `await device.wakeUp()` se `hibernating`
3. Clique do usuário (gesto — [Media doc](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md))
4. `fromTokens: [inboxDeviceToken]`
5. Telefone contato normalizado E.164 (`formatPhoneE164`)

### Done Fase 2

- [ ] Botão ligar → `startCall` → widget ativo após `peerAccept`
- [ ] Webhook cria/atualiza `Call` + bolha
- [ ] `call.end()` + webhook `ENDED` fecha bolha
- [ ] Erro `err.devices[]` exibido ao agente
- [ ] Toast em `connectivityIssue` (subset: STUN, ICE_FAILED)

**Duração:** ~1 semana.

---

## Fase 3 — Inbound (fatia vertical)

**Objetivo:** receber chamadas com `FloatingCallWidget` + multi-agente.

**Docs oficiais:** [Incoming](https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md) · [Webhook CALL](https://wavoip.gitbook.io/api/wavoip-docs/webhook-beta.md)

### Backend

| Classe | Entrega |
|--------|---------|
| `CallCreateHandler` (inbound) | Só se `inbound_calls_enabled?` |
| `Broadcaster` | `voice_call.incoming` sem SDP — [webhook-contract §5](./webhook-contract.md#5-actioncable--contrato-por-provider) |
| `Wavoip::InboundMissedPushJob` | Push VAPID se nenhum agente online |
| `DeviceHandler` | Cache `device_status` em `provider_config` |

### Frontend

| Classe | Entrega |
|--------|---------|
| `useWavoipIncomingOffer.js` | `wavoip.on('offer')` → store; `accept`/`reject` no clique |
| `useWavoipNotifications.js` | OS notification aba em background |
| `custom/.../voiceCallCableRegistry.js` | Handlers Wavoip sem SDP |
| `actionCable.js` | `# FORK:` uma linha — delega ao registry |
| `VoiceCall.vue` | `# FORK:` sem join SDP; gravação via `record_url` — [frontend-integration §12](./frontend-integration.md#12-bolha-voicecallvue) |
| `FloatingCallWidget.vue` | Usar `isBrowserVoiceProvider` — sem FORK dedicado |

### Fluxo aceitar

1. SDK emite `offer` (todos os agentes online com token).
2. Webhook `INCOMING_RING` → conversa + bolha + ActionCable.
3. Agente clica **Aceitar** → `offer.accept()` (gesto obrigatório).
4. Webhook `ACTIVE` → bolha `in_progress`.
5. Outros agentes: `acceptedElsewhere` → `dismissCall`
6. Assignee: `conversation.update!(assignee: Current.user)` no accept se auto-assign do inbox

### Done Fase 3

- [ ] Ring + widget inbound
- [ ] Aceitar/rejeitar
- [ ] `acceptedElsewhere` / `HANDLED_REMOTELY` limpa UI
- [ ] `unanswered` → bolha `no_answer`
- [ ] Agente offline: webhook cria conversa missed + **push VAPID**
- [ ] `accepted_by_agent_id` gravado no accept (PATCH call ou webhook ACTIVE)

**Duração:** 1–1,5 semana.

---

## Fase 4 — Gravação

**Objetivo:** anexar gravações Wavoip. Push offline na Fase 3.

**Docs oficiais:** [Gravação](https://wavoip.gitbook.io/api/wavoip-docs/gravacao.md) · [Webhook RECORD](https://wavoip.gitbook.io/api/wavoip-docs/webhook-beta.md)

| Entrega | Detalhe |
|---------|---------|
| `RecordHandler` | Webhook `RECORD` → `record_url` em `Call#meta` + anexo |
| Fallback gravação | `https://storage.wavoip.com/{whatsapp_call_id}` |
| `DeviceHandler` completo | Sincronizar webhook `DEVICE` com painel settings |
| Bolha `VoiceCall.vue` | Player `record_url` / anexo quando `completed` |

### Done Fase 4

- [ ] Gravação visível na bolha ou anexo
- [ ] Status dispositivo consistente webhook ↔ SDK

**Duração:** 3–5 dias.

---

## Fase 5 — Diagnóstico e mídia (opcional)

**Docs oficiais:** [Troubleshooting](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md) · [Tipos](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md) · [Webphone diagnóstico](https://wavoip.gitbook.io/api/webphone/recursos/diagnostico.md)

| Recurso | Implementação |
|---------|---------------|
| `iceDiagnostics` / `stats` / `serverStats` | `wavoipDiagnosticsCollector.js` |
| Copiar relatório JSON | Botão admin em `WavoipCallingPage` |
| `runStunProbe` | Troubleshooting rede |
| `useWavoipMedia` | Seletor mic/speaker global |

**Não** embutir `@wavoip/wavoip-webphone`.

**Duração:** 3–5 dias.

---

## Inventário FORK

Objetivo: **≤ 8 arquivos upstream** com `# FORK:` — registry em `custom/` absorve o resto.

| Arquivo | Mudança |
|---------|---------|
| `vite.shared.ts` | alias `customDashboard` |
| `inbox.js` | `WAVOIP` + reexport `isBrowserVoiceProvider` de `custom/` |
| `ChannelList.vue` | tile |
| `ChannelItem.vue` | gate `channel_voice` (+ `channel_wavoip` se piloto) |
| `ChannelFactory.vue` | map component |
| `useCallSession.js` | registry `BROWSER_VOICE_HANDLERS` |
| `actionCable.js` | **uma** delegação ao `voiceCallCableRegistry` |
| `VoiceCall.vue` | branch bolha sem SDP join |

**Não FORK** (usar `isBrowserVoiceProvider`): `FloatingCallWidget`, `ConversationCallButton`, `CallCard`, `calls.js` — importar helper de `customDashboard`.

| Arquivo `custom/` | Função |
|-------------------|--------|
| `lib/voice/browserVoiceProviders.js` | `BROWSER_VOICE_PROVIDERS`, `isBrowserVoiceProvider` |
| `lib/voice/voiceCallCableRegistry.js` | handlers whatsapp + wavoip |
| `lib/voice/voiceSessionRegistry.js` | handlers useCallSession |

**Evitar FORK** em: `WhatsappCallsController`, `useWhatsappCallSession`, `WhatsappEventsJob`, `channel_whatsapp.rb`.

Rodar `bin/fork-inventory` antes de merge.

---

## Dependências npm

```json
{
  "@wavoip/wavoip-api": "^2.5.0"
}
```

- **Não** `@wavoip/wavoip-webphone`.
- Dynamic import:

```javascript
const { Wavoip } = await import('@wavoip/wavoip-api');
```

---

## API REST — explicitamente fora do MVP

Rotas `register_attempt` / `ack_accept` da [architecture.md](./architecture.md) **adiadas**. Webhook + SDK são fonte de verdade. Reavaliar só se relatórios exigirem `accepted_by_agent_id` antes do webhook `ACTIVE`.

---

## Testes (quando solicitados)

| Camada | Foco |
|--------|------|
| `PayloadNormalizer` | [fixtures/](./fixtures/) do spike |
| `StatusMapper` | Tabela webhook only |
| `callStatusUI.js` | Tabela SDK only |
| `CallUpdateHandler` | Idempotência status terminal |
| `ConversationLinker` | Reuso conversa aberta |
| `Custom::Call` prepend | `Call.providers` inclui `wavoip` após boot |
| Composables | Mock `Wavoip` com eventos |

Sem E2E Wavoip cloud no CI.

---

## Rollout

1. `channel_voice` na conta (existente).
2. Flag fork `channel_wavoip` — ver [feature-flags.md](./feature-flags.md)
3. Piloto: 1 inbox, 1 token, 1 agente — [operations-runbook.md](./operations-runbook.md).
4. Validar: dispositivo `open` → outbound → inbound → gravação.
5. GA: habilitar `channel_wavoip` por padrão ou remover gate do tile.

---

## Estimativa total

| Escopo | Tempo |
|--------|-------|
| Fase 0 | 2–4 dias |
| Fases 1–3 (MVP atendimento) | **3–4 semanas** |
| Fases 4–5 (polish) | **+1 semana** |

---

## Checklist merge-safety

- [ ] Zero edição em `enterprise/.../whatsapp_calls_controller.rb`
- [ ] Zero edição em `useWhatsappCallSession.js`
- [ ] `prepend_mod_with` para `Call` e inbox create — não patch direto EE
- [ ] `bin/fork-inventory` atualizado
- [ ] Tile Meta `whatsapp_call` inalterado
- [ ] Dois mappers de status documentados e implementados separados
- [ ] [webhook-contract.md](./webhook-contract.md) seguido (auth, idempotência, ActionCable)
