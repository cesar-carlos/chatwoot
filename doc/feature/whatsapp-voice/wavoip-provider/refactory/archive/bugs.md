# Bugs confirmados — Wavoip (arquivado)

> Conteúdo integral preservado para consulta histórica. Ver [../CHANGELOG.md](../CHANGELOG.md)
> para o resumo condensado.

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
[sdk-reference.md](../../sdk-reference.md) nem em [official-docs.md](../../official-docs.md), que
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
conexão **antes** de chamar `wakeUpInboxDevice` e desconecta apenas a conexão que ele mesmo abriu.

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

`removePendingOffer` apagava a entrada do `offerWaiters` e cancelava o timer de timeout, mas
nunca chamava `waiter.reject()` — qualquer promise de `waitForPendingOffer` ficava pendente
para sempre se a offer fosse descartada antes de chegar (`unanswered`, `rejectedElsewhere`,
`ended` via cable). Corrigido chamando `waiter.reject(new Error('Offer cancelled'))`.

---

## BUG-02 · Alertas de chamada em inglês hardcoded para qualquer idioma

**Status:** ✅ Corrigido (R1 — jun. 2026)
**Severidade:** Média
**Arquivos:** `voiceCallCableRegistry.js`, `wavoipCallDiagnostics.js`

Ambos importavam o JSON de locale inglês diretamente em vez de usar `useI18n()`/`t`.
Corrigido recebendo `t`/`translateFn` como parâmetro nos pontos de entrada.

---

## BUG-03 · Múltiplos `EscalateRingJob` por retransmissão de INCOMING_RING

**Status:** ✅ Corrigido (R2 — jun. 2026)
**Severidade:** Média
**Arquivo:** `custom/app/services/wavoip/calls/ring_escalation_scheduler.rb`

Sem guard de idempotência — cada retransmissão do webhook agendava um novo job (o `EscalateRingJob`
não fazia nada extra pois checa `call.ringing?`, mas poluía a fila). Corrigido com lock via
`Rails.cache` com TTL igual ao timeout.

---

## BUG-04 · `isConnecting` fica `false` prematuramente em conexões concorrentes

**Status:** ✅ Corrigido (R3 — jun. 2026)
**Severidade:** Baixa
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipConnection.js`

`isConnecting` era um boolean singleton; se dois inboxes conectassem simultaneamente, o primeiro
a terminar setava `false` mesmo com o segundo ainda em progresso. Corrigido com contador atômico.

---

## BUG-05 · `activeInboxId` não é limpo ao cancelar chamada de saída

**Status:** ✅ Corrigido (R3 — jun. 2026)
**Severidade:** Baixa
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipActiveCall.js`

`clearRingingOutgoingCall` não limpava `activeInboxId`, podendo herdar o inbox errado em
chamadas subsequentes. Corrigido adicionando a limpeza.
