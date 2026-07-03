# Bugs confirmados — Wavoip

Comportamentos errados observados diretamente no código. Nenhum depende de condição externa
para se manifestar — são reproduzíveis na sequência de eventos esperada do produto.

**Status (03 jul. 2026):** os 7 itens abaixo foram **corrigidos** no código. Este documento
permanece como registro histórico do problema e da correção aplicada.

---

## BUG-06 · Botão "Acordar dispositivo" nunca chama `device.wakeUp()` do SDK

**Status:** ✅ Corrigido (03 jul. 2026)  
**Severidade:** Média  
**Arquivo:** `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/WavoipDevicePanel.vue`

### Descrição

Reportado pelo usuário ao revisar as ações de botão do painel de dispositivo (Settings →
Chamadas). O botão **"Acordar dispositivo"** (`WAKE_UP`) nunca acionava o mecanismo de wake-up
documentado pela Wavoip. `handleWakeUp` apenas repetia a verificação de status via REST:

```js
// WavoipDevicePanel.vue (antes)
const handleWakeUp = async () => {
  isWaking.value = true;
  try {
    // Calling all_info wakes a hibernating device (matches SDK wakeUp() internals).
    // refreshConnection with forceLiveCheck does exactly that via the backend.
    await refreshConnection({ forceLiveCheck: true });
    if (!isConnected.value) {
      openQrModal({ fresh: true });
    }
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isWaking.value = false;
  }
};
```

O comentário afirmava que a chamada REST `all_info` (`Wavoip::DeviceStatusService#connection_payload`)
"acorda" um dispositivo hibernando — afirmação nunca documentada em
[sdk-reference.md](../sdk-reference.md) nem em [official-docs.md](../official-docs.md), que
listam `wakeUp()` como ação **distinta** do SDK, executada sobre a conexão WebSocket
(`device.wakeUp()`), não uma leitura de status. A própria base de código já continha a
implementação correta, mas nunca usada por este botão:

```js
// useWavoipConnection.js — função já existente e testada, porém órfã (sem nenhum call site)
const wakeUpInboxDevice = async inboxId => {
  const client = await connectInbox(inboxId);
  const device = getPrimaryDevice(client);
  if (!device?.wakeUp) return false;
  return device.wakeUp();
};
```

Efeito prático: clicar em "Acordar dispositivo" com o device em `hibernating` nunca enviava o
sinal de wake-up real — apenas relia no polling/webhook para eventualmente refletir o estado,
dando a falsa impressão de que o botão "não faz nada".

### Correção

`handleWakeUp` agora chama `wakeUpInboxDevice(inboxId)` (SDK `device.wakeUp()`) antes de
reconferir o status via REST. Para não vazar uma conexão SDK nova em `wavoipClientRegistry`
quando o agente/admin que abriu a página de configurações não é membro atribuído ao inbox
(portanto sem conexão já aberta pelo `WavoipConnectionHost`), o handler registra se já havia uma
conexão **antes** de chamar `wakeUpInboxDevice` e desconecta apenas a conexão que ele mesmo abriu:

```js
const handleWakeUp = async () => {
  isWaking.value = true;
  const hadSdkConnection = Boolean(getWavoipClientEntry(inboxId.value));
  try {
    await wakeUpInboxDevice(inboxId.value);
    await refreshConnection({ forceLiveCheck: true });
    if (!isConnected.value) {
      openQrModal({ fresh: true });
    }
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    if (!hadSdkConnection) {
      disconnectInbox(inboxId.value).catch(() => {});
    }
    isWaking.value = false;
  }
};
```

Cobertura: `WavoipDevicePanel.spec.js` — chamada a `wakeUpInboxDevice`, desconexão condicional
quando não havia conexão prévia, e preservação da conexão quando já existia (owned by
`WavoipConnectionHost`).

**Achado relacionado (não um bug, mas corrigido na mesma revisão):** `copyDiagnostics` não
tratava falhas de `navigator.clipboard.writeText` (rejeita sem permissão ou documento sem foco),
falhando silenciosamente sem alertar o usuário. Agora envolvido em try/catch com
`showDeviceActionError` e um estado de loading (`isCopyingDiagnostics`) no botão.

---

## BUG-01 · Deadlock em `acceptIncomingCall` quando offer é removida antes de chegar

**Status:** ✅ Corrigido (R1 — jun. 2026)  
**Severidade:** Alta  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipIncomingOffer.js`

### Descrição

`removePendingOffer` apaga a entrada do `offerWaiters` e cancela o timer de timeout, mas
**nunca chama `waiter.reject()`**. Qualquer promise criada por `waitForPendingOffer` que
aguardasse aquela offer fica resolvida: o timer foi cancelado e o `resolve` jamais é chamado.

```js
// useWavoipIncomingOffer.js — linhas 26–33
export const removePendingOffer = callId => {
  pendingOffers.delete(callId);
  const waiter = offerWaiters.get(callId);
  if (waiter) {
    clearTimeout(waiter.timer);
    offerWaiters.delete(callId);
    // ← waiter.reject() NUNCA é chamado → promise trava para sempre
  }
};
```

O fluxo problemático:

1. Cable event `voice_call.incoming` chega → agente clica "atender"
2. `acceptIncomingCall` chama `waitForPendingOffer(callId)` pois a offer SDK ainda não chegou
3. A offer é descartada antes de chegar (ex: `unanswered`, `rejectedElsewhere`, ou `ended` via cable)
4. `removePendingOffer` é chamado → timer cancelado, nenhum `reject()` → a promise pende indefinidamente
5. `acceptIncomingCall` nunca retorna; a UI fica presa no estado "conectando"

### Correção

```js
export const removePendingOffer = callId => {
  pendingOffers.delete(callId);
  const waiter = offerWaiters.get(callId);
  if (waiter) {
    clearTimeout(waiter.timer);
    offerWaiters.delete(callId);
    waiter.reject(new Error('Offer cancelled'));   // ← adicionar
  }
};
```

`acceptIncomingCall` em `useWavoipCallSession.js` já está envolto em try/catch implícito
no chamador (`useCallSession.js`); o `reject` é propagado corretamente.

---

## BUG-02 · Alertas de chamada em inglês hardcoded para qualquer idioma

**Status:** ✅ Corrigido (R1 — jun. 2026)  
**Severidade:** Média  
**Arquivos:**
- `custom/app/javascript/dashboard/lib/voice/voiceCallCableRegistry.js`
- `custom/app/javascript/dashboard/lib/wavoip/wavoipCallDiagnostics.js`

### Descrição

Ambos os arquivos importam o JSON de locale inglês diretamente e passam strings brutas para
`useAlert`, ignorando o idioma ativo do usuário.

```js
// voiceCallCableRegistry.js — linha 3
import conversationI18n from 'dashboard/i18n/locale/en/conversation.json';
// ...
useAlert(conversationI18n.CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE); // ← sempre em inglês
```

`useWavoipIncomingOffer.js` faz corretamente com `useI18n()`:
```js
offer.on?.('acceptedElsewhere', () => {
  useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE'));
});
```

### Correção

**`voiceCallCableRegistry.js`** pode ser convertido para composable (já usa `useAlert`),
recebendo `t` como parâmetro ou importando via `useI18n` na raiz do módulo.

**`wavoipCallDiagnostics.js`** é uma função utilitária (não composable). A string de
mensagem deve ser recebida como parâmetro no ponto de entrada, resolvida pelo chamador
(`wireCallDiagnostics`) que já está dentro de um setup:

```js
// wavoipCallDiagnostics.js
export const wireCallDiagnostics = (call, { inboxId, callId, translateFn }) => {
  call.on('connectivityIssue', issue => {
    const msg = translateFn
      ? translateFn(`CONVERSATION.WAVOIP_CONNECTIVITY.${issue?.code || 'GENERIC'}`)
      : 'Call connection issue';
    useAlert(msg);
  });
};
```

Chamadores em `useWavoipActiveCall.js` e `useWavoipOutboundCall.js` passam `translateFn: t`.

---

## BUG-03 · Múltiplos `EscalateRingJob` por retransmissão de INCOMING_RING

**Status:** ✅ Corrigido (R2 — jun. 2026)  
**Severidade:** Média  
**Arquivo:** `custom/app/services/wavoip/calls/ring_escalation_scheduler.rb`

### Descrição

`RingEscalationScheduler#schedule` não tem guard de idempotência. Se o Wavoip retransmitir
o evento `INCOMING_RING` (reconexão WebSocket, retry de webhook), cada evento gera um novo
job agendado:

```ruby
# ring_escalation_scheduler.rb
def schedule
  timeout = inbox.channel.ring_timeout_seconds
  return unless timeout.positive?
  Wavoip::EscalateRingJob.set(wait: timeout.seconds).perform_later(call.id)
  # ← sem verificação se já foi agendado
end
```

`EscalateRingJob` guarda `call.ringing?` antes de executar, então só o primeiro job
a correr faz algo — mas N jobs ficam na fila do Sidekiq consumindo recursos.

### Correção

Opção A — flag Redis com TTL igual ao timeout:

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

Opção B — `sidekiq-unique-jobs` com `lock: :until_executed` no job (prefere se já usado no projeto).

---

## BUG-04 · `isConnecting` fica `false` prematuramente em conexões concorrentes

**Status:** ✅ Corrigido (R3 — jun. 2026)  
**Severidade:** Baixa  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipConnection.js`

### Descrição

`isConnecting` é um `ref` singleton compartilhado por todas as caixas de entrada. Se dois
inboxes iniciam conexão simultaneamente, o primeiro a concluir seta `isConnecting.value = false`
enquanto o segundo ainda está em progresso:

```js
// useWavoipConnection.js
const promise = (async () => {
  isConnecting.value = true;
  try { /* ... */ }
  finally {
    isConnecting.value = false;  // ← dispara quando o PRIMEIRO termina, não todos
  }
})();
```

Componentes que exibem spinner com base em `isConnecting` vão piscar para o estado "pronto"
prematuramente.

### Correção

Substituir o boolean por contador atômico:

```js
let connectingCount = 0;
const isConnecting = computed(() => connectingCount > 0);

// na finally:
connectingCount = Math.max(0, connectingCount - 1);
```

Ou tornar `isConnecting` um `ref` por inbox (Map de inbox → bool).

---

## BUG-05 · `activeInboxId` não é limpo ao cancelar chamada de saída

**Status:** ✅ Corrigido (R3 — jun. 2026)  
**Severidade:** Baixa  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipActiveCall.js`

### Descrição

`setRingingOutgoingCall` define `activeInboxId = inboxId`. Mas `clearRingingOutgoingCall`
não limpa `activeInboxId`:

```js
export const clearRingingOutgoingCall = () => {
  ringingSdkCall = null;
  ringingProviderCallId = null;
  // activeInboxId NÃO é limpo aqui
};
```

Se uma chamada de saída for cancelada antes de `peerAccept`, `activeInboxId` retém o
valor da chamada cancelada. Chamadas subsequentes — especialmente de outros inboxes — podem
herdar o `inboxId` errado até que uma nova chamada defina o valor.

### Correção

```js
export const clearRingingOutgoingCall = () => {
  ringingSdkCall = null;
  ringingProviderCallId = null;
  activeInboxId = null;   // ← adicionar
};
```

Se `activeInboxId` for compartilhado entre chamada ativa e chamada tocando de saída,
separar em `activeInboxId` e `ringingInboxId`.
