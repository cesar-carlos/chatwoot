# Spike Wavoip — notas (template)

Preencher na Fase 0. Renomear para `spike-notes.md` (gitignored ou interno).

**Doc oficial:** [official-docs.md](./official-docs.md) · [llms.txt](https://wavoip.gitbook.io/api/llms.txt)

**Data:** YYYY-MM-DD  
**Responsável:**  
**Token / device:** (mascarar — só últimos 4 chars)

---

## 1. Dispositivo

| Campo | Valor |
|-------|-------|
| Status inicial | |
| QR necessário? | sim / não |
| Tempo até `open` | |
| `contact.phone` após parear | |
| `official` ou `unofficial` | |
| Teste `hibernating` → `wakeUp()` | ok / falhou |

---

## 2. Outbound

| Campo | Valor |
|-------|-------|
| Número destino | |
| `startCall` ok? | |
| `peerAccept` após (s) | |
| `connectivityIssue` observados | |
| `connectionStatus` (unofficial) | |

---

## 3. Inbound

| Campo | Valor |
|-------|-------|
| `offer` recebido? | |
| `accept()` com gesto ok? | |
| 2 abas: `acceptedElsewhere`? | |

---

## 4. Webhook

| Evento | Recebido? | Notas |
|--------|-----------|-------|
| `CALL` CREATE inbound | | |
| `CALL` UPDATE ACTIVE | | |
| `CALL` UPDATE ENDED | | |
| `RECORD` | | |
| `DEVICE` | | |

### Correlação SDK ↔ webhook

| Fluxo | ID SDK | `whatsapp_call_id` | Iguais? | Regra determinística alternativa |
|-------|--------|--------------------|---------|----------------------------------|
| Outbound | | | | |
| Inbound | | | | |

Registrar também a ordem e o atraso entre offer/call do SDK e `CALL CREATE`.

### Anomalias do payload

- [ ] Salvar os **bytes brutos** recebidos antes de `JSON.parse`
- [ ] Campo `type` duplicado no JSON?
- [ ] Após parse, `type` representa o evento (`CALL`) ou o modo (`HUMANIZED`/`ROBOTIC`)?
- [ ] `whatsapp_call_id` sempre string?
- [ ] `phone` formato E.164?
- [ ] `direction` chega como `OUTCOMING`, `OUTGOING` ou ambos?

**Copiar fixtures reais para:** [fixtures/](./fixtures/) (substituir templates).

---

## 5. Rails smoke (Fase 0.8)

```ruby
inbox = Inbox.joins(:channel).find_by(channel_type: 'Channel::Wavoip') # ou stub
# Ou com inbox WhatsApp só para testar builder:
call = Voice::InboundCallBuilder.perform!(
  inbox: inbox,
  from_number: '+5511999999999',
  call_sid: 'spike-test-id',
  provider: :wavoip,
  extra_meta: { wavoip_call_type: 'official' }
)
call.provider # => 'wavoip'
Call.providers.keys # deve incluir 'wavoip'
```

| Check | ok? |
|-------|-----|
| `Call.providers` inclui `wavoip` | |
| Bolha `voice_call` criada | |
| Enum sem erro | |

---

## 6. Decisões pós-spike

| Decisão | Escolha |
|---------|---------|
| Seguir para Fase 1 | go / no-go |
| Estratégia de correlação SDK/webhook | |
| Ajustes no `PayloadNormalizer` | |
| Restrições multiagente | |
| Bloqueadores | |
