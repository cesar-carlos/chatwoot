# Runbook operacional — Wavoip

Guia para admins e suporte quando a integração não funciona como esperado.

**Relacionado:** [sdk-reference.md](./sdk-reference.md) · [webhook-contract.md](./webhook-contract.md) · [inbox-setup.md](./inbox-setup.md) · [official-docs.md](./official-docs.md)

---

## Checklist de onboarding (semáforo)

Exibir em **Settings → Chamadas** (`WavoipOnboardingChecklist.vue`):

| # | Passo | Como verificar |
|---|-------|----------------|
| 1 | Token configurado | `device_token` presente |
| 2 | Webhook no painel Wavoip | Admin marcou ack + último webhook &lt; 24h (opcional) |
| 3 | Dispositivo `open` | `WavoipDevicePanel` badge verde |
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
| Device não `open` | Settings → parear QR ou `pairingCode` |
| `hibernating` | Clicar **Acordar** (`wakeUp`) |
| `WAITING_PAYMENT` | Regularizar conta em app.wavoip.com |
| `EXTERNAL_INTEGRATION_ERROR` | Verificar integração Evolution/gateway no Wavoip |
| Agente offline | Marcar availability **online** |
| Contato sem telefone E.164 | Editar contato |

### Chamada inbound não toca

| Causa | Ação |
|-------|------|
| Agente offline | Ficar online; push só na Fase 3+ |
| `inbound_calls_enabled: false` | Settings inbox → habilitar inbound |
| Token errado / outro inbox | Conferir token no device panel |
| Aba sem foco, sem permissão Notification | Permitir notificações no browser |
| iOS Safari | Instalar PWA ou manter aba aberta |

### Webhook não chega

| Causa | Ação |
|-------|------|
| URL errada no Wavoip | Copiar de Settings; incluir `?secret=` |
| `FRONTEND_URL` incorreto | `.env` / Installation Config |
| Firewall | Liberar POST para `/webhooks/wavoip/*` |
| Secret rotacionado | Atualizar URL no painel Wavoip |

Ver logs: `Wavoip::ProcessWebhookJob` (sem payload em produção).

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
| Fase 4 não implementada | Aguardar deploy |
| Fallback manual | `https://storage.wavoip.com/{whatsapp_call_id}` |

---

## Rotação de credenciais

### `device_token`

1. Gerar novo token em app.wavoip.com/devices
2. Settings inbox → colar novo token → salvar
3. Agente recarrega dashboard (reconecta SDK)

### `webhook_secret`

1. Settings → **Regenerar secret**
2. Copiar nova URL completa
3. Atualizar no painel Wavoip → Webhook
4. Secret antigo invalida imediatamente

---

## Habilitar conta piloto

```ruby
# Rails console
account = Account.find(ID)
account.enable_features!('channel_voice')
account.enable_features!('channel_wavoip') # se flag fork ativa
```

Migration `channel_wavoip` é **somente fork** — não existe em `upstream/develop`.
