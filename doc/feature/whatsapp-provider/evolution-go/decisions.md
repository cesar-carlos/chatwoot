# Decisões fechadas — Provider Evolution Go

Decisões de implementação registradas para evitar retrabalho. **Status:** levantamento aprovado para planejamento (jun/2026). Validar no spike antes de codificar.

---

## 1. Rota webhook

| Decisão | Valor |
|---------|-------|
| **Rota** | `POST /webhooks/evolution_go/:instance_name` |
| **Controller** | `Custom::Webhooks::EvolutionGoController` |
| **Job** | `Webhooks::WhatsappEventsJob` (prepend) |

**Motivo:** distinto de `/webhooks/evolution/:instance_name` (Evolution API Node) — evita colisão se operador rodar ambos.

**URL registrada no connect:**

```
https://{FRONTEND_URL}/webhooks/evolution_go/{instance_name}
```

Configurar em `ConnectionService#connect` via body `webhookUrl` — **não** existe `POST /webhook/set`.

---

## 2. Autenticação do webhook

| Decisão | Valor |
|---------|-------|
| **Método primário** | Query `?token=` com secret gerado no create do inbox |
| **Método secundário** | Header `Authorization: Bearer {webhook_secret}` se Evolution Go suportar headers custom no connect |
| **Envelope `apikey`** | **Não disponível** no body Go — diferente da Evolution API |

```ruby
# EvolutionGoController#authenticate_webhook!
def authenticate_webhook!
  channel = find_channel_by_instance_name(params[:instance_name])
  return head :not_found unless channel

  secret = channel.provider_config['webhook_secret']
  token = params[:token].presence || request.headers['Authorization']&.remove(/^Bearer /)

  return head :unauthorized unless secret.present? &&
    ActiveSupport::SecurityUtils.secure_compare(token.to_s, secret.to_s)

  @channel = channel
end
```

Registrar URL completa: `#{FRONTEND_URL}/webhooks/evolution_go/#{name}?token=#{webhook_secret}`

---

## 3. Resolução do channel no job

| Decisão | Valor |
|---------|-------|
| **Lookup** | `provider = 'evolution_go'` e `provider_config->>'instance_name' = :instance_name` |
| **Regra** | **1 instância Go = 1 inbox** |

Índice recomendado (migration fork):

```ruby
add_index :channel_whatsapp, "(provider_config->>'instance_name')",
          unique: true,
          where: "provider = 'evolution_go'",
          name: 'index_channel_whatsapp_evolution_go_instance_name'
```

`phone_number` obrigatório após `GET /instance/status` → `data.myJid`.

---

## 4. Autenticação REST — duas chaves

| Decisão | Valor |
|---------|-------|
| **`global_api_key`** | Operações admin: create, list, delete |
| **`instance_token`** | Connect, QR, status, send |
| **Wizard** | Operador informa `base_url` + `global_api_key`; após create, persiste `instance_token` |

Alternativa: operador cria instância no painel Go e cola `instance_token` no wizard (modo "instância existente").

---

## 5. Formato `sendText` — path e body

| Decisão | Valor |
|---------|-------|
| **Path** | `POST /send/text` — confirmado OpenAPI oficial |
| **Body** | `{ "number": "...", "text": "..." }` |
| **Header** | `apikey: instance_token` |
| **Quoted** | `{ quoted: { messageId, participant } }` — schema Go, não Baileys `quoted.key` |

Doc: [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message)

---

## 6. `source_id` outbound

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `response.dig('data', 'Info', 'ID')` — struct whatsmeow PascalCase |
| **Fallback** | `response.dig('data', 'messageId')` se presente |
| **Não usar** | `key.id` (formato Baileys/Evolution API Node) |

---

## 7. Echo `fromMe` no inbound

| Decisão | Valor |
|---------|-------|
| **MVP** | Ignorar `MESSAGE` com `data.key.fromMe: true` |
| **Fase 2+** | Campo `ignore_from_me_echo` default `true` |

---

## 8. Janela 24h e templates

| Decisão | Valor |
|---------|-------|
| **Janela** | `MessageWindowService` prepend → `nil` para `evolution_go` |
| **Templates** | `send_templates_as_text: true` — viram `send_text` |
| **UI** | Ocultar features cloud-only |

Reusar prepend da Fase 0 com capability `unlimited_session: true`.

---

## 9. Grupos WhatsApp

| Decisão | Valor |
|---------|-------|
| **MVP** | `ignore_groups: true` no create/advanced-settings + filtro `@g.us` no normalizer |
| **Fase posterior** | Suporte a grupos como conversas separadas |

---

## 10. Provider key separado

| Decisão | Valor |
|---------|-------|
| **Key** | `evolution_go` — **não** `evolution` |
| **Motivo** | Contratos REST, eventos e auth incompatíveis — ver [differences-from-evolution-api.md](./differences-from-evolution-api.md) |

---

## 11. Reuso de código Evolution API

| Decisão | Valor |
|---------|-------|
| **ApiClient** | Classe nova `EvolutionGo::ApiClient` |
| **Normalizer** | Classe nova — mapear `MESSAGE` não `MESSAGES_UPSERT` |
| **Infra Fase 0** | Compartilhar registry + prepends |
| **Wizard Vue** | Componente separado ou prop `engine=go` — avaliar na implementação |

---

## 12. Mutex e batch no job

Evolution Go envia **um evento por POST** (não batch `data[]` como Evolution API em alguns casos).

Prepend deve expor `contact_sender_id` compatível com payload **já normalizado**.

---

## 13. QR e ActionCable

| Decisão | Valor |
|---------|-------|
| **Canal** | `evolution_go:connection:{inbox_id}` |
| **Eventos** | `qrcode`, `connection` |
| **Fallback** | Polling `GET /instance/qr` + `GET /instance/status` a cada 3s |

---

## 14. Segredos no `provider_config`

| Campo | Tratamento |
|-------|------------|
| `global_api_key` | Write-only; GET masked |
| `instance_token` | Write-only; GET masked |
| `webhook_secret` | Gerado no create; nunca expor em logs |
| `proxy_password` | Write-only |

---

## 15. Licença Evolution Go

| Decisão | Valor |
|---------|-------|
| **Escopo fork** | Documentar pré-requisito; operador ativa licença no servidor Go |
| **Código Chatwoot** | Não implementar fluxo de licença — fora do escopo |

---

## 16. Defaults das regras (fork)

| Campo | Default |
|-------|---------|
| `sign_msg` | `false` |
| `ignore_groups` | `true` |
| Reabrir conversa | `inbox.lock_to_single_conversation: true` |
| `merge_brazil_contacts` | `true` |
| `send_templates_as_text` | `true` |

Detalhe: [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## 17. Inbound `source_id`

| Decisão | Valor |
|---------|-------|
| **Campo primário** | `data.key.id` no webhook `MESSAGE` |
| **Outbound (envio)** | `data.Info.ID` — ver §6 |
| **Validação** | Confirmar ambos no spike — são campos distintos |

---

## 18. Evento inbound canônico

| Decisão | Valor |
|---------|-------|
| **Evento** | `MESSAGE` (não `MESSAGES_UPSERT`) |
| **Echo** | Ignorar `SEND_MESSAGE` no job |

---

## 19. Webhook no connect

| Decisão | Valor |
|---------|-------|
| **Config** | `webhookUrl` + `subscribe` no body de `POST /instance/connect` |
| **Persistir** | Array `subscribe` em `provider_config` para reconnect |

---

## 20. Status API — casing

| Decisão | Valor |
|---------|-------|
| **OpenAPI** | `Connected`, `LoggedIn`, `Name` (PascalCase) |
| **Implementação** | `ApiClient` aceita PascalCase e camelCase até spike |

---

## 21. Wizard — proxy via backend

| Decisão | Valor |
|---------|-------|
| **Chamadas REST Go** | Sempre via **backend Chatwoot** (`ConnectionService`) — nunca `global_api_key` no browser |
| **Endpoints internos** | Ver [frontend-wizard-spec.md § API](./frontend-wizard-spec.md#api-dashboard-contrato) |
| **Motivo** | Segurança keys + CORS + licença Go no servidor |
| **Status** | **✅ Fechado** (jun/2026) |

---

## 22. Persistência `global_api_key`

| Decisão | Valor |
|---------|-------|
| **Persistir no channel** | **Sim** — write-only masked em `provider_config` |
| **Uso** | `DELETE /instance/delete/{id}`, `GET /instance/all`, reconnect admin |
| **Modo "instância existente"** | `global_api_key` opcional no wizard — obrigatório só para delete/list admin |
| **Alternativa rejeitada** | Só env vars servidor CW — quebra multi-tenant |

**Status:** **✅ Fechado** (jun/2026)

---

## 23. Reconnect e webhook

| Decisão | Valor |
|---------|-------|
| **Reconnect** | `POST /instance/connect` com `webhookUrl` + `subscribe` **sempre reenviados** |
| **Fonte** | `provider_config.webhook_secret`, `instance_name`, array `subscribe` persistido |
| **Motivo** | Evolution Go não tem `POST /webhook/set` — connect é o único ponto de configuração |

`ConnectionService#reconnect!` deve montar URL: `#{FRONTEND_URL}/webhooks/evolution_go/#{name}?token=#{secret}`.

Detalhe operação: [troubleshooting.md § Reconnect](./troubleshooting.md).

---

## Histórico

| Data | Decisão |
|------|---------|
| jun/2026 | Levantamento completo; provider `evolution_go` separado; webhook auth por query token |
| jun/2026 | ADR §22 `global_api_key` fechado; §23 reconnect sempre reenvia webhook no connect |
