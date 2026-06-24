# Referência SDK — `@wavoip/wavoip-api`

Mapeamento da documentação oficial do pacote npm para implementação no Chatwoot. **Somente browser** — não usar no Rails.

**Índice completo doc oficial:** [official-docs.md](./official-docs.md)

**Versão verificada em 19 jun. 2026:** `2.5.0`. O spike deve usar versão exata;
atualizações exigem repetir os testes de contrato.

**Fontes primárias (SDK):**

- [Dispositivo](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md)
- [Mídia](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md)
- [Chamadas recebidas](https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md)
- [Chamadas realizadas](https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md)
- [Chamada ativa](https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md)
- [Tipos](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md)
- [Solução de problemas](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md)

---

## 1. Instância raiz

```typescript
import { Wavoip } from '@wavoip/wavoip-api';

const wavoip = new Wavoip({
  tokens: [deviceToken],
  platform: 'chatwoot',
});
```

| Método / evento | Uso Chatwoot | Composable |
|-----------------|--------------|------------|
| `on('offer', handler)` | Inbound ring | `useWavoipIncomingOffer` |
| `startCall({ to, fromTokens? })` | Outbound | `useWavoipOutboundCall` |
| `getDevices()` / `addDevices()` | Lifecycle por inbox | `useWavoipConnection` |
| `wakeUpDevices()` | Antes de outbound se `hibernating` | `useWavoipConnection` |
| `getMultimediaDevices()` | Seletor mic/speaker | `useWavoipMedia` (Fase 5+) |

---

## 2. Dispositivo (`Device`)

Cada token = um `Device` com WebSocket persistente. **Chamadas só funcionam com status `open`.**

### 2.1 Status (`DeviceStatus`)

Fonte: [Device](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md) · [Tipos](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md)

| Status SDK | Significado | UI Chatwoot (settings / banner) |
|------------|-------------|----------------------------------|
| `disconnected` | WS caiu; reconexão automática (até 3x) | “Reconectando…” |
| `close` | Conectado, sem WhatsApp vinculado | “Vincule o número” |
| `connecting` | QR disponível | Mostrar QR (`qrCodeChanged`) |
| `open` | Pronto para chamadas | Verde “Conectado” |
| `restarting` | Reiniciando | “Reiniciando — aguarde” |
| `hibernating` | Inativo 2,5+ min | Botão “Acordar” → `wakeUp()` |
| `BUILDING` | Inicializando | “Preparando dispositivo…” |
| `WAITING_PAYMENT` | Conta Wavoip sem pagamento | Alerta admin |
| `EXTERNAL_INTEGRATION_ERROR` | Falha integração (Evolution etc.) | Alerta + link doc Wavoip |

Webhook `DEVICE` usa subset legado (`open`/`close` → futuro `connected`/`disconnected`) — mapear ambos em `DeviceHandler`.

### 2.2 Eventos do dispositivo

| Evento | Payload | Onde usar |
|--------|---------|-----------|
| `statusChanged` | `DeviceStatus` | `WavoipCallingPage` indicador |
| `qrCodeChanged` | `string \| undefined` | Modal QR no settings (se pareamento no Chatwoot) |
| `contactChanged` | `Contact \| undefined` | Validar `phone` do inbox vs `contact.phone` |

### 2.3 Métodos do dispositivo

| Método | Uso |
|--------|-----|
| `restart()` | Admin troubleshooting |
| `logout()` | Desvincular WhatsApp |
| `wakeUp()` | Antes de `startCall` se hibernando |
| `pairingCode(phone)` | Alternativa ao QR — exibir código no settings |

**Impacto no inbox-setup:** na criação só pedimos **token**; pareamento QR/código fica em **Settings → Chamadas** (`WavoipDevicePanel.vue`), não no passo 2 do wizard — a menos que o dispositivo já esteja `open` no painel Wavoip antes de criar o inbox.

---

## 3. Mídia (`MediaManager`)

Fonte: [Mídia](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md)

| API | Uso Chatwoot |
|-----|--------------|
| `getMultimediaDevices()` | Lista mics/speakers |
| `wavoip.multimedia` | Dispositivo ativo atual |
| Troca de microfone | `FloatingCallWidget` mute já cobre mic da call; seletor global = Fase 5 |

**Regra do navegador:** `offer.accept()` deve ocorrer em gesto do usuário, conforme a
documentação oficial. Por consistência com políticas de mídia/autoplay, iniciar outbound
também deve partir do clique do agente.

`AudioContext` é suspenso até a primeira chamada; retoma no accept/start.

---

## 4. Chamada recebida (`Offer`)

Fonte: [Incoming](https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md)

### 4.1 Propriedades

| Campo | Tipo | → Chatwoot `calls` store |
|-------|------|--------------------------|
| `id` | `string` | `id` |
| `type` | `official` \| `unofficial` | `meta.callType` |
| `peer.phone` | E.164 | `phone` |
| `peer.displayName` | string \| null | `name` |
| `peer.profilePicture` | string \| null | avatar no widget (opcional) |
| `device_token` | string | validar inbox |

### 4.2 Métodos

| Método | Quando |
|--------|--------|
| `accept()` | Clique Aceitar no `FloatingCallWidget` |
| `reject()` | Clique Rejeitar |

### 4.3 Eventos `Offer`

| Evento | Ação Chatwoot |
|--------|---------------|
| `acceptedElsewhere` | `dismissCall` + toast |
| `rejectedElsewhere` | idem |
| `unanswered` | teardown + bolha via webhook |
| `ended` | teardown |
| `iceDiagnostics` / `connectivityIssue` | `wavoipDiagnosticsCollector` |

---

## 5. Chamada realizada (`CallOutgoing`)

Fonte: [Outgoing](https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md)

```typescript
const { call, err } = await wavoip.startCall({
  to: contactPhone,
  fromTokens: [inboxDeviceToken], // restringir ao inbox
});
```

| Evento | Ação |
|--------|------|
| `peerAccept` | `CallActive` → `setCallActive` + timer |
| `peerReject` | bolha failed (webhook confirma) |
| `unanswered` | bolha `no_answer` |
| `ended` | teardown se cancelou antes de atender |

Erro `err.devices[]` — exibir qual token falhou (útil multi-inbox).

---

## 6. Chamada ativa (`CallActive`)

Fonte: [Active](https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md)

| Método | `FloatingCallWidget` |
|--------|----------------------|
| `mute()` / `unmute()` | Botão mute |
| `end()` | Encerrar |

| Evento | Uso |
|--------|-----|
| `ended` | Teardown + upload/gravação via webhook |
| `peerMute` / `peerUnmute` | Indicador UI |
| `connectionStatus` | Banner `reconnecting` (relay `unofficial`) |
| `stats` / `serverStats` | Diagnóstico admin |
| `error` | Toast erro transporte |

`connection_status`: `connecting` → `connected` → `reconnecting` (até 30s) → `disconnected`.

---

## 7. Dois vocabulários de status (crítico)

**Não confundir** status do **webhook HTTP** com status do **SDK**.

### 7.1 Webhook `CALL.status` → `Call.status` (Rails)

| Webhook | Chatwoot `Call.status` |
|---------|------------------------|
| `INCOMING_RING`, `OUTGOING_RING`, `OUTGOING_CALLING`, `CONNECTING` | `ringing` |
| `ACTIVE` | `in_progress` |
| `ENDED` | `completed` |
| `NOT_ANSWERED` | `no_answer` |
| `REJECTED`, `FAILED`, `CONNECTION_LOST` | `failed` |
| `HANDLED_REMOTELY` | ignorar ring / `completed` |

Implementar em `Calls::StatusMapper.from_webhook(status)`.

### 7.2 SDK `CallStatus` → UI browser

Fonte: [Tipos](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md)

| SDK `CallStatus` | UI widget state |
|------------------|-----------------|
| `CALLING` | incoming ringing |
| `RINGING` | outbound ringing |
| `ACTIVE` | ongoing |
| `ENDED` | teardown |
| `REJECTED` | failed |
| `NOT_ANSWERED` | no_answer |
| `FAILED` | failed |
| `DISCONNECTED` | failed / reconnect |

Implementar em `lib/wavoip/callStatusUI.js` — **não** misturar com mapper Rails.

### 7.3 `CallType`

| Valor | Transporte | Implicação |
|-------|------------|------------|
| `official` | WebRTC nativo WhatsApp | STUN/TURN crítico |
| `unofficial` | Relay WebSocket Wavoip | `connectionStatus` reconnect |

Persistir em `Call#meta['wavoip_call_type']`.

---

### 7.4 `offer.accept()` return shape

Doc: [Chamada Ativa](https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md)

`offer.accept()` resolves to `{ call: CallActive, err }` — **not** a bare `CallActive`.

Chatwoot normalizes via `unwrapWavoipSdkResult()` in `custom/.../lib/wavoip/wavoipSdkResult.js`:

```javascript
const { call, err } = unwrapWavoipSdkResult(await offer.accept());
if (err || !call) throw new Error(err?.message || err);
setActiveCall(call, { providerCallId: offer.id, inboxId });
```

`Device.connectionStatusChanged` (WebSocket) is tracked separately from `statusChanged` (WhatsApp) in `wavoipDeviceStatus.js` / `useWavoipConnection`.

### 7.5 Multi-agente — `voice_call.accepted`

Emitido por `Wavoip::Calls::Broadcaster#broadcast_agent_accepted` quando:

- Agente aceita no browser → `PATCH /api/v1/accounts/:id/calls/:id`
- Webhook inbound `ACTIVE` → `CallUpsertService#emit_broadcasts`

Payload inclui `accepted_by_agent_id`. Handler `voiceCallCableRegistry.onAccepted` dispensa outras abas exceto a que aceitou (`getActiveProviderCallId` / `accepted_by_agent_id === currentUser`).

### 7.6 Dismiss vs reject (inbound)

| Ação UI | SDK | Efeito |
|---------|-----|--------|
| Recusar (phone-decline) | `offer.reject()` | Contato para de tocar |
| Dismiss (✕) inbound Wavoip | `offer.reject()` via `dismissCall` | Mesmo que recusar — evita ring órfão |

---

## 8. Tipos úteis (import)

```typescript
import type {
  CallActive, CallOutgoing, Offer,
  CallPeer, CallStats, ServerCallStats,
  CallStatus, CallType, DeviceStatus,
  IceDiagnostics, ConnectivityIssue,
  TransportStatus,
} from '@wavoip/wavoip-api';
```

`CallPeer` para enriquecer contato:

```typescript
type CallPeer = {
  phone: string;
  displayName: string | null;
  profilePicture: string | null;
  muted: boolean;
};
```

---

## 9. Troubleshooting (`connectivityIssue`)

Fonte: [Solução de problemas](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md)

| Código | Causa típica | i18n key sugerida |
|--------|--------------|-------------------|
| `STUN_UNREACHABLE` | Firewall UDP / STUN bloqueado | `WAVOIP_CONNECTIVITY.STUN_UNREACHABLE` |
| `ICE_GATHERING_TIMEOUT` | STUN/TURN lento | `WAVOIP_CONNECTIVITY.ICE_GATHERING_TIMEOUT` |
| `ICE_CONNECTION_FAILED` | Sem TURN / NAT | `WAVOIP_CONNECTIVITY.ICE_CONNECTION_FAILED` |
| `NO_HOST_CANDIDATES` | VPN / flag Chrome WebRTC | `WAVOIP_CONNECTIVITY.NO_HOST_CANDIDATES` |
| `SYMMETRIC_NAT_SUSPECTED` | CGNAT — precisa TURN | `WAVOIP_CONNECTIVITY.SYMMETRIC_NAT_SUSPECTED` |

Handler em `useWavoipActiveCall` / `useWavoipIncomingOffer` → toast + buffer no `wavoipDiagnosticsCollector`.

`runStunProbe(servers)` — botão em `WavoipCallingPage` (admin).

---

## 10. Mapa composable → SDK

| Composable Chatwoot | Objetos SDK |
|---------------------|-------------|
| `useWavoipConnection` | `Wavoip`, `Device`, `wakeUp`, `statusChanged` |
| `useWavoipIncomingOffer` | `Offer`, `wavoip.on('offer')` |
| `useWavoipOutboundCall` | `CallOutgoing`, `startCall` |
| `useWavoipActiveCall` | `CallActive`, mute/end/events |
| `useWavoipMedia` | `getMultimediaDevices`, `multimedia` |
| `useWavoipDevicePanel` | `qrCodeChanged`, `pairingCode`, `restart` |
| `wavoipDiagnosticsCollector` | `iceDiagnostics`, `connectivityIssue`, `stats` |

Cada composable **&lt; 200 linhas** — ver [architecture.md](./architecture.md).

---

## 11. Pré-requisitos antes de chamar

Checklist runtime (antes de `startCall` / aceitar `offer`):

1. `Device.status === 'open'`
2. Se `hibernating` → `await device.wakeUp()`
3. Agente **online** no Chatwoot
4. `inbound_calls_enabled` (inbound) no `provider_config`
5. Gesto do usuário no clique (accept/start)

Se `WAITING_PAYMENT` ou `EXTERNAL_INTEGRATION_ERROR` → desabilitar botão ligar + banner no inbox settings.
