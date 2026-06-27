# Runbook operacional — Wavoip

Guia para admins e suporte quando a integração não funciona como esperado.

**Relacionado:** [contracts-and-ports.md](./contracts-and-ports.md) · [sdk-reference.md](./sdk-reference.md) · [webhook-contract.md](./webhook-contract.md) · [inbox-setup.md](./inbox-setup.md) · [official-docs.md](./official-docs.md) · [spike-notes.md](./spike-notes.md)

---

## Produção piloto (Jun 2026)

| Item | Valor (exemplo) |
|------|-----------------|
| Account | 2 |
| Inbox id | 42 |
| Device phone | `556697193168` (status `open`) |
| Webhook URL pattern | `{FRONTEND_URL}/webhooks/wavoip/{webhook_key}` |
| Exemplo URL | `https://chat.se7esistemassinop.com.br/webhooks/wavoip/mz5uFxCZ4tVZn94Nm5osnqCQ` |

> **Erro comum:** usar `/webhooks/wavoip/42` (inbox id) em vez de `/webhooks/wavoip/{webhook_key}`. A chave opaca é gerada em `channel_wavoip.webhook_key`, não é o id do inbox.

API (admin): `wavoip_webhook_url`, `wavoip_setup_pending` — ver [inbox-setup.md §7](./inbox-setup.md#7-settings-edição-posterior).

---

## Checklist painel Wavoip (obrigatório)

Configurar URL **não basta** — o painel exige toggle e seleção de eventos:

1. [app.wavoip.com](https://app.wavoip.com) → **Devices** → selecionar o dispositivo (ex. `556697193168`)
2. **Integrações → Webhook**
3. Colar URL completa: `{FRONTEND_URL}/webhooks/wavoip/{webhook_key}`
4. **Ativar** o toggle do webhook
5. Selecionar eventos: **CALL** (obrigatório), **DEVICE** (recomendado)
6. Salvar — primeiro POST válido define `webhook_verified_at` em `provider_config`

### Verificar entrega no nginx

```bash
# Deve aparecer POST de origem Wavoip (não só curl de testes)
grep 'POST /webhooks/wavoip/' /var/log/nginx/chatwoot_access_443.log | grep -v curl
```

Sidekiq: `Wavoip::ProcessWebhookJob` enfileirado após POST válido (sem payload em produção nos logs).

---

## Checklist de onboarding (semáforo)

Verificação manual — **não há componente Vue dedicado no MVP**. Use **Settings → Chamadas**
(`WavoipCallingPage.vue`) para URL/status do webhook e o alerta pós-criação em `Wavoip.vue`
para copiar a URL durante o setup.

| # | Passo | Como verificar |
|---|-------|----------------|
| 1 | Token configurado | `wavoip_device_token_configured` na API ou Settings |
| 2 | Webhook no painel Wavoip | `wavoip_setup_pending: false` após primeiro evento válido |
| 3 | Dispositivo `open` | Status no painel [app.wavoip.com](https://app.wavoip.com) → Devices |
| 4 | Número confere | `contact.phone` do device = `phone_number` do inbox |
| 5 | Agente online | Availability = online no dashboard |
| 6 | `channel_voice` habilitado | Super admin / plano |

Botão **Testar ligação** (Fase 2+): outbound para número de teste interno.

---

## Sintomas comuns

### Tile “Chamada Wavoip” cinza

| Causa | Ação |
|-------|------|
| `channel_voice` desabilitado na conta | Super Admin → Account → Features → Voice Channel |
| Flag `channel_wavoip` desabilitada (piloto) | Habilitar feature fork se em rollout gradual |

### Botão ligar desabilitado

| Causa | Ação |
|-------|------|
| Device não `open` | Settings → Chamadas → escanear **QR code** ou usar **Get pairing code** no painel do device |
| `hibernating` | Clicar **Acordar** (`wakeUp`) |
| `WAITING_PAYMENT` | Regularizar conta em app.wavoip.com |
| `EXTERNAL_INTEGRATION_ERROR` | Verificar integração Evolution/gateway no Wavoip |
| Agente offline | Marcar availability **online** |
| Contato sem telefone E.164 | Editar contato |

### Chamada inbound não toca

| Causa | Ação |
|-------|------|
| **Histórico Wavoip só mostra DEVICE (sem CALL)** | Painel → Webhook → habilitar evento **CALL** no device correto; fechar app.wavoip.com no celular durante teste |
| **Log `Skipped create: missing or inbox peer phone`** | Payload live usa `caller`/`receiver` (não `peer`) — corrigido em `PayloadNormalizer` (Jun 2026); confirmar deploy |
| Agente offline / aba fechada | Ficar **online** e manter o dashboard aberto; push in-app segue as regras de roteamento |
| Agente não listado na aba **Agentes** | Adicionar na aba Agentes do inbox |
| Device `close` / não vinculado | Settings → Chamadas → escanear QR ou pairing code (`WavoipDevicePanel`) |
| Admin fora da lista de Agentes | Settings → Chamadas → ligar **Include account administrators**, ou adicionar como agente |
| `incoming_call_offline_fallback: none` e ninguém online | Ajustar **When no agent is online** em Settings → Chamadas |
| `inbound_calls_enabled: false` | Settings inbox → habilitar inbound |
| Token errado / outro inbox | Conferir token em app.wavoip.com/devices |
| Aba sem foco, sem permissão Notification | Permitir notificações no browser |
| iOS Safari | Instalar PWA ou manter aba aberta |

Ver roteamento completo: [inbox-setup.md §3.6](./inbox-setup.md#36-seção--roteamento-de-chamadas-inbound-settings) · [architecture.md §3.6](./architecture.md#36-actioncable).

### Toque continua após rejeitar ou após chamador desligar

| Sintoma | Causa provável | Comportamento esperado (27 jun. 2026) |
|---------|----------------|--------------------------------------|
| Agente rejeitou mas ainda ouve o toque | Deploy antigo sem `silenceCallRingtone` | Ao rejeitar (✕) ou recusar, o som para **imediatamente** neste browser; outros agentes/dispositivos continuam tocando até alguém atender ou o chamador desligar |
| Toque não para quando chamador desliga | IDs cable (`whatsapp_call_id`) ≠ SDK (`Offer.id`) sem reconciliação | Corrigido: `wavoipOfferId` + `onEnded`/`unanswered`/`ended` removem a entrada e param o ringtone; toast **"O chamador encerrou a ligação"** |
| Agente quer só aviso visual (sem som) | Preferência não configurada | Clicar no ícone **bell** no card de chamada incoming — preferência salva em `localStorage` por usuário |
| Bell silenciado mas ainda vê o card | Comportamento correto | Mute do bell afeta **som**, não a notificação visual |

Ver [frontend-integration.md §6.4](./frontend-integration.md#64-ringtone-e-preferências-do-agente).

### Webhook não chega

| Causa | Ação |
|-------|------|
| **URL usa inbox id em vez de `webhook_key`** | Corrigir para `/webhooks/wavoip/{webhook_key}` — **não** `/webhooks/wavoip/42` |
| URL errada no Wavoip | Copiar de Settings → Chamadas (`WavoipCallingPage`) ou alerta pós-criação em `Wavoip.vue`; campo API: `wavoip_webhook_url` |
| Toggle/eventos não habilitados no painel | Ativar webhook + selecionar evento **CALL** no device correto |
| `FRONTEND_URL` incorreto | `.env` / Installation Config |
| Firewall | Liberar POST para `/webhooks/wavoip/*` |
| Secret rotacionado | Atualizar URL no painel Wavoip |

Ver logs: `Wavoip::ProcessWebhookJob` (sem payload em produção). Nginx: `grep webhooks/wavoip` (ver seção acima).

### Segurança do webhook

| Item | Detalhe |
|------|---------|
| Autenticação | Chave opaca em `channel_wavoip.webhook_key` no path (`/webhooks/wavoip/{key}`) — sem HMAC de body no MVP |
| Risco | URL completa vazada (logs, Referer, painel Wavoip) permite forjar POSTs até rotação da key |
| Mitigação | Rate limit ~120 POST/min por key (`rack_attack`); rotacionar key em Settings → Chamadas após incidente |
| Resposta | HTTP 202 imediato; processamento assíncrono via Sidekiq |

### Áudio mudo / ICE falhou

| `connectivityIssue` | Ação |
|---------------------|------|
| `STUN_UNREACHABLE` | Liberar UDP 3478; testar fora de VPN corporativa |
| `ICE_CONNECTION_FAILED` | Verificar TURN; tentar rede móvel |
| `SYMMETRIC_NAT_SUSPECTED` | Usar TURN; chamada `unofficial` (relay) |
| `NO_HOST_CANDIDATES` | Desativar flag Chrome “Anonymize local IPs” |

Ver [Troubleshooting Wavoip](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md) e [official-docs.md](./official-docs.md).

### Outro agente atendeu (`acceptedElsewhere`)

Comportamento esperado com **um token por inbox**. Primeiro `accept()` ganha. Demais agentes veem toast e ring para.

### Gravação ausente

| Causa | Ação |
|-------|------|
| Webhook `RECORD` não configurado no Wavoip | Habilitar gravação no painel |
| UI RECORD | Pós-MVP — pipeline backend existe (`RecordHandler`) |
| Fallback manual | `https://storage.wavoip.com/{whatsapp_call_id}` |

---

## Rotação de credenciais

### `device_token`

1. Gerar novo token em app.wavoip.com/devices
2. Settings inbox → colar novo token → salvar
3. Agente recarrega dashboard (reconecta SDK)

### `webhook_key`

1. Settings → **Regenerar URL**
2. Copiar a nova URL completa
3. Atualizar no painel Wavoip → Webhook
4. A chave anterior invalida imediatamente

---

## Habilitar conta piloto

```ruby
# Rails console
account = Account.find(ID)
account.enable_features!('channel_voice')
account.enable_features!('channel_wavoip') # se flag fork ativa
```

---

## Produção validada (checklist)

| # | Verificação | Comando / ação |
|---|-------------|----------------|
| 1 | Smoke automatizado | `WAVOIP_INBOX_ID=106 WAVOIP_TEST_PEER_PHONE=+5566999050312 bin/wavoip-pilot-verify` (W1 + I1 + I2 + O2) |
| 2 | Webhook live (não curl) | `grep 'POST /webhooks/wavoip/' /var/log/nginx/chatwoot_access_443.log \| grep -v curl` |
| 3 | Sidekiq processa CALL | Logs `[WAVOIP] processed inbox_id=… event_type=CALL` |
| 4 | Outbound E2E | SDK RINGING → ACTIVE + `Call` + `voice_call` no DB |
| 5 | Inbound E2E | Widget + webhook `INCOMING_RING` + push (se VAPID) |
| 6 | G0.4 multi-agente | Dois browsers online; segundo agente vê toast `ACCEPTED_ELSEWHERE` |
| 7 | Hang-up | SDK permanece conectado para próximo inbound |
| 8 | Inbound off | Settings toggle → webhook não cria `Call` |

### G0.4 — procedimento multi-agente

1. Dois usuários agentes na mesma inbox Wavoip, ambos **online**
2. Browser A e B no dashboard (`/app`)
3. Iniciar chamada inbound para o device pareado
4. Agente A aceita no widget
5. Agente B deve: widget sumir + alerta *Another agent answered this call*
6. Registrar em [spike-notes.md](./spike-notes.md) (Pass/Fail)

### E2E manual — `+5566999050312`

| Flow | Steps |
|------|-------|
| Outbound | Agent online → conversation → call → `peerAccept` → end → `voice_call` bubble |
| Inbound | Close app.wavoip.com → call from `+5566999050312` → confirm **CALL** line in Wavoip history (not only DEVICE) → widget Accept → audio |
| Webhook | `WAVOIP_INBOX_ID=106 WAVOIP_TEST_PEER_PHONE=+5566999050312 bin/wavoip-pilot-verify` |
| Playwright | `cd tests/playwright && pnpm playwright:run tests/e2e/wavoip` (env: `WAVOIP_WEBHOOK_KEY`, `WAVOIP_INBOX_ID`, `WAVOIP_INBOX_PHONE`) |

Prerequisite: only one browser client per device token (close Wavoip panel during agent tests).

---

## Métricas e alertas (suporte)

| Sinal | Onde buscar |
|-------|-------------|
| Webhook aceito | Rails log `[WAVOIP] webhook accepted inbox_id=…` |
| Job processado | `[WAVOIP] processed inbox_id=… event_type=…` |
| Webhook drop | `[WAVOIP] Dropping webhook: inbox_id=… not found` |
| Recording fetch fail | `[WAVOIP] recording fetch failed call_id=…` |
| Throttle bootstrap | Rack::Attack log `wavoip_sdk_bootstrap` |

Migration `channel_wavoip` é **somente fork** — não existe em `upstream/develop`.
