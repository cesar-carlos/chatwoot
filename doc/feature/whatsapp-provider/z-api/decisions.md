# Decisões fechadas — Provider Z-API

Decisões de implementação registradas para evitar retrabalho. **Status:** aprovado para planejamento (jun/2026). Confirmar `update-every-webhooks` path no E2E.

---

## 1. Provider key

| Decisão | Valor |
|---------|-------|
| **Key** | `zapi` — **não** `z-api` nem `z_api` |
| **Motivo** | Alinhado com `gaps-and-blockers.md` e registry existente |

---

## 2. Rota webhook

| Decisão | Valor |
|---------|-------|
| **Rota** | `POST /webhooks/zapi/:instance_id` |
| **Controller** | `Custom::Webhooks::ZapiController` |
| **Job** | `Webhooks::WhatsappEventsJob` (prepend) |

**Motivo:** Z-API permite (e recomenda via doc) **uma URL para todos os callbacks** — demux por campo `type`.

**URL registrada:**

```
https://{FRONTEND_URL}/webhooks/zapi/{instance_id}?token={webhook_token}
```

Configurar via `PUT .../update-every-webhooks` com `notifySentByMe: false` — ou 4× PUT individuais se endpoint bulk falhar no E2E.

---

## 3. Autenticação do webhook

| Decisão | Valor |
|---------|-------|
| **Método** | Query `?token=` com `webhook_token` gerado no create do inbox |
| **Secundário** | Validar `instanceId` no body === `params[:instance_id]` |
| **Z-API nativo** | Sem HMAC documentado nos callbacks |

```ruby
def authenticate_webhook!
  channel = Channel::Whatsapp.find_by(
    provider: 'zapi',
    provider_config: { instance_id: params[:instance_id] }
  )
  return head :not_found unless channel

  secret = channel.provider_config['webhook_token']
  token = params[:token].presence

  return head :unauthorized unless secret.present? &&
    ActiveSupport::SecurityUtils.secure_compare(token.to_s, secret.to_s)

  @channel = channel
end
```

---

## 4. Resolução do channel no job

| Decisão | Valor |
|---------|-------|
| **Lookup** | `provider = 'zapi'` e `provider_config->>'instance_id' = :instance_id` |
| **Regra** | **1 instância Z-API = 1 inbox** |

Índice recomendado (migration fork):

```ruby
add_index :channel_whatsapp, "(provider_config->>'instance_id')",
          unique: true,
          where: "provider = 'zapi'",
          name: 'index_channel_whatsapp_zapi_instance_id'
```

---

## 5. Autenticação REST

| Decisão | Valor |
|---------|-------|
| **Path** | `instance_id` + `instance_token` embutidos na URL |
| **Header** | `Client-Token: {client_token}` — obrigatório se ativado na conta Z-API |
| **Wizard MVP** | Operador cola os 3 valores do painel Z-API |

Doc: [client-token](https://developer.z-api.io/security/client-token.md)

`client_token` é por **conta** (não por instância) — pode ser compartilhado entre inboxes da mesma conta.

---

## 6. `source_id` outbound

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `response['messageId']` |
| **Fallback** | `response['id']` |
| **Não usar** | `zaapId` como `source_id` (ID interno fila) |

---

## 7. `source_id` inbound e status

| Decisão | Valor |
|---------|-------|
| **Receive** | `messageId` |
| **MessageStatusCallback** | `ids[0]` |
| **DeliveryCallback** | `messageId` |

---

## 8. Echo `fromMe`

| Decisão | Valor |
|---------|-------|
| **MVP** | Ignorar `ReceivedCallback` com `fromMe: true` |
| **notifySentByMe** | `false` ao registrar webhooks |
| **received-delivery** | Não habilitar no MVP |

---

## 9. Janela 24h e templates

| Decisão | Valor |
|---------|-------|
| **Janela** | `MessageWindowService` prepend → `nil` para `zapi` |
| **Templates Meta** | `sync_templates` noop — Z-API não tem templates WABA |
| **UI** | Ocultar template picker cloud-only |
| **Capability** | `unlimited_session: true` |

---

## 10. Grupos, canais e newsletter

| Decisão | Valor |
|---------|-------|
| **MVP** | Filtrar `isGroup: true` e `isNewsletter: true` no normalizer |
| **Fase posterior** | Grupos como escopo separado (igual Evolution) |

---

## 11. Provider separado

| Decisão | Valor |
|---------|-------|
| **Não reutilizar** | `EvolutionService`, `EvolutionNormalizer`, `EvolutionController` |
| **Reutilizar** | Registry, prepends, padrão wizard, `MessageWindowService` |

---

## 12. Demux de eventos no controller/job

| `type` | Ação |
|--------|------|
| `ReceivedCallback` | Inbound mensagem |
| `DeliveryCallback` | Confirmação envio (opcional — status já cobre parte) |
| `MessageStatusCallback` | Status read/delivered/sent |
| `DisconnectedCallback` | `connection_status` → disconnected |
| `ConnectedCallback` | `connection_status` → connected |
| Outros | Ignorar (log debug) |

---

## 13. QR e ActionCable

| Decisão | Valor |
|---------|-------|
| **Canal** | `zapi:connection:{inbox_id}` |
| **Eventos** | `qrcode`, `connection` |
| **Fallback** | Polling `GET .../status` + `GET .../qr-code/image` a cada **10–20s** (doc Z-API: QR invalida ~20s) |
| **Sucesso** | `status.connected == true` |

---

## 14. Segredos no `provider_config`

| Campo | Tratamento |
|-------|------------|
| `instance_token` | Write-only; GET masked |
| `client_token` | Write-only; GET masked |
| `webhook_token` | Gerado no create; nunca logar |
| `partner_auth_token` | Não persistir em produção se usar Partners API |

---

## 15. Provisionamento instância

| Decisão | Valor |
|---------|-------|
| **MVP** | Credenciais manuais do painel Z-API |
| **Fase 2** | API Partners `POST /instances/integrator/on-demand` |
| **Motivo MVP** | Evita dependência de contrato partner no piloto |

---

## 16. Defaults das regras (fork)

| Campo | Default |
|-------|---------|
| `ignore_groups` | `true` |
| `notify_sent_by_me` | `false` |
| Reabrir conversa | `inbox.lock_to_single_conversation: true` |
| `merge_brazil_contacts` | `true` |
| `send_templates_as_text` | N/A — sem templates |

Detalhe: [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## 17. Mídia inbound (Fase 2)

| Decisão | Valor |
|---------|-------|
| **Download** | HTTP GET direto na `imageUrl` / `audioUrl` / etc. do payload |
| **Prazo** | Baixar no job — URLs expiram ~30 dias |
| **Sem endpoint download** | Diferente Evolution Go — Z-API entrega URL pública no webhook |

---

## 18. Contato / phone resolution

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `phone` do payload (E.164 sem `+`) |
| **LID** | Suportar `senderLid` como fallback se `phone` ausente — ver [lid](https://developer.z-api.io/tips/lid.md) |
| **Grupos** | Usar `participantPhone` só se suporte futuro |

---

## 19. Wizard — proxy via backend

| Decisão | Valor |
|---------|-------|
| **Chamadas REST Z-API** | Sempre via **backend** (`ConnectionService`) |
| **Motivo** | `instance_token` e `client_token` não expor no browser |
| **Status** | **✅ Fechado** (jun/2026) |

---

## 20. Registro webhooks — estratégia

| Decisão | Valor |
|---------|-------|
| **Preferido** | `PUT .../update-every-webhooks` uma chamada |
| **Fallback** | 4× PUT (`received`, `delivery`, `message-status`, `disconnected`) |
| **notifySentByMe** | `false` |

---

## Histórico

| Data | Decisão |
|------|---------|
| jun/2026 | Provider `zapi` separado; webhook multiplexado; auth query token |
| jun/2026 | Payloads oficiais confirmados em developer.z-api.io (ReceivedCallback, DeliveryCallback, MessageStatusCallback) |
