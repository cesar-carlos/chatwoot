# Plano de implementação — Wavoip

Fases concretas, entregas e critérios de done. Código novo em `custom/` salvo `# FORK:` listados.

**Pré-requisitos:** [README.md](./README.md) · [architecture.md](./architecture.md) · feature `channel_voice` habilitada na conta.

---

## Fase 0 — Validação (spike)

**Objetivo:** confirmar viabilidade antes de modelar canal.

| # | Tarefa | Done |
|---|--------|------|
| 0.1 | Criar dispositivo em [app.wavoip.com/devices](https://app.wavoip.com/devices) | Token obtido |
| 0.2 | HTML/Vite mínimo com `@wavoip/wavoip-api`: `on('offer')`, `startCall` | Áudio bidirecional |
| 0.3 | Configurar webhook apontando para ngrok → log payload `CALL` | JSON capturado |
| 0.4 | Testar 2 abas, mesmo token — observar `acceptedElsewhere` | Comportamento documentado |
| 0.5 | Verificar `type`: `official` vs `unofficial` no dispositivo | Anotado no runbook |

**Saída:** `doc/feature/whatsapp-voice/wavoip-provider/spike-notes.md` (opcional, time interno).

**Duração:** 2–4 dias.

---

## Fase 1 — Infraestrutura de canal

**Objetivo:** inbox Wavoip criável; token persistido; sem chamadas ainda.

### Backend

| Entrega | Arquivo |
|---------|---------|
| Migration `channel_wavoip` | `db/migrate/…_create_channel_wavoip.rb` |
| Model | `custom/app/models/channel/wavoip.rb` |
| Policy | `custom/app/policies/channel/wavoip_policy.rb` |
| Inbox creation | prepend `Enterprise::InboxesController` ou controller `custom/` |
| Webhook route stub | `custom/.../webhooks/wavoip_controller.rb` → 200 + log |

### Frontend

| Entrega | Arquivo |
|---------|---------|
| Tile `wavoip_call` | `ChannelList.vue` `# FORK:` |
| Gate tile | `ChannelItem.vue` `# FORK:` — `channel_voice` + feature flag opcional |
| Wizard setup | `custom/.../channels/WavoipCall.vue` — nome inbox, phone, device_token |
| Settings | `custom/.../WavoipCallingPage.vue` — token, display_name, webhook URL copiável |

### `# FORK:` nesta fase

```javascript
// ChannelItem.vue — wavoip_call
if (key === 'wavoip_call') {
  return props.enabledFeatures.channel_voice;
}
```

```javascript
// inbox.js
export const VOICE_CALL_PROVIDERS = { ..., WAVOIP: 'wavoip' };
```

### Done Fase 1

- [ ] Admin cria inbox tipo Wavoip com token
- [ ] Settings exibem URL webhook `{FRONTEND_URL}/webhooks/wavoip/{phone}`
- [ ] `voice_enabled?` true com token + `channel_voice`
- [ ] Nenhuma regressão em canais existentes

**Duração:** ~1 semana.

---

## Fase 2 — Outbound na conversa

**Objetivo:** agente liga a partir da conversa; bolha `voice_call` no histórico.

### Backend

| Classe | Entrega |
|--------|---------|
| `PayloadNormalizer` | Parse webhook `CALL` |
| `CallUpsertService` | `Call` provider `wavoip` |
| `MessageSyncService` | Bolha outbound |
| `StatusMapper` | Estados ring → terminal |
| Handlers `CallCreate` / `CallUpdate` | Outbound path |

### Frontend

| Classe | Entrega |
|--------|---------|
| `wavoipClientRegistry.js` | Instância por inbox |
| `useWavoipConnection.js` | Conecta quando agente online no inbox |
| `useWavoipOutboundCall.js` | `startCall` com telefone do contato |
| `useWavoipCallSession.js` | Facade |
| `useCallSession.js` | `# FORK:` branch Wavoip |
| `ConversationCallButton.vue` | Habilitar para `wavoip` |

### Done Fase 2

- [ ] Botão ligar na conversa inicia chamada Wavoip
- [ ] Webhook cria/atualiza `Call` + bolha `voice_call`
- [ ] Widget mostra chamada ativa (outbound)
- [ ] Encerrar no widget chama `call.end()` e webhook `ENDED` atualiza bolha

**Duração:** ~1 semana.

---

## Fase 3 — Inbound + widget

**Objetivo:** receber chamadas com `FloatingCallWidget` + roteamento multi-agente.

### Backend

| Classe | Entrega |
|--------|---------|
| `ConversationLinker` | Contato/conversa no `CALL CREATE` inbound |
| `Broadcaster` | `voice_call.incoming` com `provider: wavoip` |
| `CallCreateHandler` (inbound) | Só se `inbound_calls_enabled?` |

### Frontend

| Classe | Entrega |
|--------|---------|
| `useWavoipIncomingOffer.js` | `offer` → store; accept/reject |
| `useWavoipNotifications.js` | OS notification aba em background |
| `actionCable.js` | `# FORK:` aceitar `provider === 'wavoip'` |
| `FloatingCallWidget.vue` | Mute via Wavoip se necessário `# FORK:` mínimo |

### Fluxo aceitar

1. `offer` chega no SDK (browser com token).
2. Webhook `INCOMING_RING` → conversa + ActionCable.
3. Agente clica Aceitar → `offer.accept()` (gesto usuário — requisito SDK).
4. Webhook `ACTIVE` → status bolha.

### Done Fase 3

- [ ] Inbound toca ringtone / widget
- [ ] Aceitar/rejeitar funciona
- [ ] `acceptedElsewhere` limpa UI nos outros agentes
- [ ] Chamada perdida (`unanswered`) atualiza bolha `no_answer`
- [ ] Agente offline: webhook ainda cria conversa (missed)

**Duração:** 1–2 semanas.

---

## Fase 4 — Gravação e device health

**Objetivo:** anexar gravações Wavoip; monitorar dispositivo.

| Entrega | Detalhe |
|---------|---------|
| `RecordHandler` | Webhook `RECORD` + `record_url` → `Call#meta` + anexo na mensagem |
| `DeviceHandler` | Status `open`/`close`/`error` → flag no inbox / alerta admin |
| Settings UI | Indicador “dispositivo conectado” |

### Done Fase 4

- [ ] `record_url` visível na bolha ou como anexo
- [ ] Admin vê quando dispositivo Wavoip desconecta

**Duração:** 3–5 dias.

---

## Fase 5 — Diagnóstico (opcional)

**Objetivo:** suporte operacional sem depender do webphone React.

Reimplementar subset da [doc de diagnóstico Wavoip](https://wavoip.gitbook.io/api/webphone/recursos/diagnostico.md) via `@wavoip/wavoip-api`:

| Recurso | Implementação Chatwoot |
|---------|------------------------|
| `iceDiagnostics` / `connectivityIssue` | `wavoipDiagnosticsCollector.js` — buffer últimos 20 |
| `stats` / `serverStats` | Painel debug em settings (admin only) |
| Copiar relatório JSON | Botão em `WavoipCallingPage` |
| Banner `STUN_UNREACHABLE` | Toast i18n quando `connectivityIssue` |

**Não** embutir aba Diagnóstico do webphone — construir painel Vue mínimo.

**Duração:** 3–5 dias.

---

## Dependências npm

```json
{
  "@wavoip/wavoip-api": "^2.5.0"
}
```

- **Não** adicionar `@wavoip/wavoip-webphone` (React).
- Import dinâmico em módulos Wavoip para não inflar bundle global:

```javascript
const { Wavoip } = await import('@wavoip/wavoip-api');
```

---

## Testes (quando solicitados)

| Camada | Foco |
|--------|------|
| `PayloadNormalizer` | Fixtures JSON webhook |
| `StatusMapper` | Tabela de estados |
| `ConversationLinker` | Reuso conversa aberta |
| Composables | Mock `Wavoip` class com eventos |

Evitar specs de integração E2E com Wavoip cloud no CI.

---

## Rollout

1. Feature flag conta: `channel_voice` (existente).
2. Flag opcional fork: `channel_wavoip` em `custom/` para rollout gradual.
3. Habilitar em 1 conta piloto → validar webhook + 1 agente → expandir.

---

## Estimativa total

| Escopo | Tempo |
|--------|-------|
| Fases 0–3 (MVP atendimento) | **3–5 semanas** |
| Fases 4–5 (polish) | **+1–2 semanas** |

---

## Checklist final de merge-safety

- [ ] Zero edição em `enterprise/.../whatsapp_calls_controller.rb`
- [ ] Zero edição em `useWhatsappCallSession.js`
- [ ] `bin/fork-inventory` lista todos `# FORK:`
- [ ] Doc atualizada em `wavoip-provider/`
- [ ] Tile Meta `whatsapp_call` inalterado
