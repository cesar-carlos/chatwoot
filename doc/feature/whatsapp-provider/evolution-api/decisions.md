# Decisões fechadas — Provider Evolution

Decisões de implementação registradas para evitar retrabalho na Fase 0–1. **Status:** aprovadas para o fork (jun/2026).

---

## 1. Rota webhook

| Decisão | Valor |
|---------|-------|
| **Rota** | `POST /webhooks/evolution/:instance_name` |
| **Controller** | `Custom::Webhooks::EvolutionController` |
| **Job** | `Webhooks::WhatsappEventsJob` (prepend) |

**Motivo:** o controller upstream (`Webhooks::WhatsappController`) e o job assumem payload Meta/360dialog (`phone_number` na URL ou `object: whatsapp_business_account`). O envelope Evolution (`event`, `instance`, `data`) colide com essa validação.

**URL registrada na Evolution:**

```
https://{FRONTEND_URL}/webhooks/evolution/{instance_name}
```

**Por que `FRONTEND_URL`:** o Chatwoot já monta webhooks de channel com essa variável (`app/models/inbox.rb`, `Whatsapp::WebhookSetupService`, `Whatsapp360DialogService`). A Evolution deve usar o mesmo host público que Telegram, SMS e WhatsApp cloud — não `BACKEND_URL` interno.

Configurar em `ConnectionService#set_webhook` com `byEvents: false` (evento único na URL base).

---

## 2. Autenticação do webhook

| Decisão | Valor |
|---------|-------|
| **Método primário** | Validar `apikey` do envelope contra `provider_config.api_key` |
| **Método secundário (opcional)** | Query `?token=` com secret gerado no create do inbox |
| **IP allowlist** | Fora do escopo MVP |

```ruby
# EvolutionController#authenticate_webhook!
def authenticate_webhook!
  channel = find_channel_by_instance_name(params[:instance_name])
  return head :not_found unless channel

  envelope_key = params[:apikey].presence || request.headers['apikey']
  return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(
    envelope_key.to_s, channel.provider_config['api_key'].to_s
  )

  @channel = channel
end
```

**Motivo:** Evolution envia `apikey` no body do webhook (`webhook.controller.ts` → `emit()`). Token na URL sozinho não cobre o caso em que a URL vaza sem o secret no query string.

---

## 3. Resolução do channel no job

| Decisão | Valor |
|---------|-------|
| **Lookup** | `Channel::Whatsapp` onde `provider = 'evolution'` e `provider_config->>'instance_name' = :instance_name` |
| **Regra operacional** | **1 instância Evolution = 1 inbox** `provider: 'evolution'` no fork |
| **Multi-account** | Dois accounts Chatwoot **não** devem compartilhar o mesmo `instance_name` apontando para webhooks distintos — colisão de rota |

Índice recomendado (migration fork, Fase 1) — **único global** no banco:

```ruby
add_index :channel_whatsapp, "(provider_config->>'instance_name')",
          unique: true,
          where: "provider = 'evolution'",
          name: 'index_channel_whatsapp_evolution_instance_name'
```

**Alternativa futura** (multi-tenant mesmo servidor Evolution): índice via `inboxes.account_id` + `instance_name` — fora do MVP; exigiria join no lookup do controller.

`phone_number` continua obrigatório após conexão (`CONNECTION_UPDATE` / `sender` do envelope).

---

## 4. Formato `sendText` — body da requisição

| Decisão | Valor |
|---------|-------|
| **Formato enviado** | `{ "number": "...", "text": "..." }` (campo `text` plano) |
| **Fallback** | Se HTTP 400 com mensagem de validação, retry com `{ "textMessage": { "text": "..." } }` |
| **Versão Evolution alvo** | Código em `/root/evolution-api` (schema `textMessageSchema`) |

Implementar em `ApiClient#send_text` — ver [spec-design.md](./spec-design.md).

**Validação obrigatória:** um teste de integração manual contra o servidor Evolution de staging antes de fechar Fase 1; registrar resultado em `spec/fixtures/evolution/README.md` § Validação sendText.

---

## 5. `source_id` outbound

| Decisão | Valor |
|---------|-------|
| **Campo** | `response['key']['id']` (Baileys) |
| **Prefixo `WAID:`** | **Não usar** — prefixo é da integração Evolution→Chatwoot legada |

`EvolutionService#process_response` sobrescreve `BaseService#process_response` (que espera `messages[0].id` da Meta).

---

## 6. Echo `fromMe` no inbound

| Decisão | Valor |
|---------|-------|
| **MVP** | Ignorar `MESSAGES_UPSERT` com `data.key.fromMe: true` (filtro **hardcoded** na Fase 1) |
| **Fase 2+** | Campo configurável `ignore_from_me_echo` default `true` na UI |

Outbound já cria mensagem com `source_id` no Chatwoot; processar echo duplicaria.

**Nota `isIntegration`:** a flag `textMessage(..., true)` na Evolution só evita re-entrada quando `chatwoot.enabled` está ativo no Baileys. Com integração legada desligada ([§7](#7-integração-chatwoot-na-evolution)), o provider nativo **não** depende dessa flag — validar em spike que echo não duplica mesmo assim.

---

## 7. Integração Chatwoot na Evolution

| Decisão | Valor |
|---------|-------|
| **Sempre** | `chatwoot.enabled = false` — nunca chamar `POST /chatwoot/set` |
| **Verificação** | `ConnectionService#ensure_chatwoot_integration_disabled` após create/connect |

---

## 8. Janela 24h e templates

| Decisão | Valor |
|---------|-------|
| **Janela** | `MessageWindowService` prepend → `nil` para `evolution` |
| **Templates** | `send_templates_as_text: true` default — templates viram `sendText` |
| **UI** | Ocultar embedded signup, template picker Meta, CSAT cloud-only |

---

## 9. Grupos WhatsApp

| Decisão | Valor |
|---------|-------|
| **MVP** | Ignorar grupos (`@g.us`) — `groups_ignore: true` no `POST /instance/create` + filtro no normalizer |
| **Fase 2** | UI para `groups_ignore` e `ignore_jids` |
| **Fase posterior** | Suporte a grupos como conversas separadas |

---

## 10. Import histórico (Fase 4)

| Decisão | Valor |
|---------|-------|
| **Abordagem** | API Evolution (`findContacts`, `findMessages`) — **sem** SQL direto no Postgres Chatwoot |
| **Job** | `Custom::Whatsapp::Evolution::ImportJob` (background, rate-limited) |
| **Design detalhado** | Ver [spec-design.md § Import](./spec-design.md#import-fase-4) |

---

## 11. Mídia inbound (Fase 2)

| Decisão | Valor |
|---------|-------|
| **Preferência** | `webhookBase64: true` na config do webhook para MVP mídia |
| **Alternativa** | `POST /chat/getBase64FromMediaMessage/:instanceName` se base64 desabilitado |

---

## 12. Mutex no job (album / concorrência)

O prepend `WhatsappEventsJob` deve expor `contact_sender_id` compatível com payload **já normalizado** (chaves top-level `contacts` + `messages`), igual ao 360dialog — não passar envelope Evolution cru para `super`.

```ruby
def perform(params = {})
  return super(params) unless evolution_envelope?(params)

  channel = find_evolution_channel(params)
  return unless channel

  case params['event']
  when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
    Array.wrap(params['data']).each do |data_item|
      normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer
        .new(channel, params.merge('data' => data_item)).perform
      super(normalized.merge(phone_number: channel.phone_number)) if normalized.present?
    end
  when 'CONNECTION_UPDATE', 'QRCODE_UPDATED'
    Custom::Whatsapp::Evolution::ConnectionService.new(channel).handle_event(params)
  end
end
```

`phone_number` no merge garante que `find_channel_by_url_param` do job upstream funcione se o prepend delegar para `super`.

---

## 13. `data` em lote no webhook

| Decisão | Valor |
|---------|-------|
| **Formato** | `data` pode ser **Hash** (um messageRaw) ou **Array** de messageRaw |
| **Normalizer** | `Array.wrap(envelope['data']).each` — processar cada item; retorno do job usa último normalizado ou merge por evento |

Documentar fixture `messages_upsert_batch.json` quando capturado no [validation-checklist.md](./validation-checklist.md).

---

## 14. Idempotência e retry Evolution

| Decisão | Valor |
|---------|-------|
| **Dedup inbound** | Reusar Redis lock por `source_id` em `IncomingMessageBaseService` (upstream) |
| **Retry Evolution** | `webhook.controller.ts` reenvia com backoff em falha HTTP — Chatwoot deve responder **200** rápido e processar async |
| **Logs** | Sanitizar `apikey` do envelope antes de logar |

---

## 15. Segredos no `provider_config`

| Decisão | Valor |
|---------|-------|
| **`api_key`** | Write-only na API do dashboard; GET retorna masked (`••••••••`) ou omite |
| **`proxy_password`** | Mesmo tratamento |
| **Serializer** | Prepend ou `as_json` custom no channel evolution — ver [provider-config-mapping.md](./provider-config-mapping.md) |

---

## 16. Arquitetura do job inbound (ADR)

| Opção | Prós | Contras | Decisão |
|-------|------|---------|---------|
| **A** — Prepend `WhatsappEventsJob` | Reusa pipeline 360dialog; menos rotas | Risco de regressão cloud/default se detecção falhar | **✅ MVP** |
| **B** — `EvolutionWebhookJob` dedicado | Isolamento total (padrão Wavoip) | Duplica roteamento de status/contacts | Reavaliar se prepend gerar bugs |

Implementar **A** na Fase 0–1. Se testes de regressão falharem, migrar para **B** sem mudar normalizer.

---

## 17. QR e eventos de conexão na UI

| Decisão | Valor |
|---------|-------|
| **Canal ActionCable** | `evolution:connection:{inbox_id}` |
| **Eventos** | `qrcode_updated`, `connection_update` |
| **Fallback** | Polling `GET /instance/connect` a cada 3s no wizard até `open` |
| **Emitter** | `ConnectionService#handle_event` após webhook ou poll |

---

## 18. Health no inbox (Fase 3)

| Decisão | Valor |
|---------|-------|
| **Endpoint** | `GET /instance/connectionState/:instanceName` |
| **UI** | Badge em settings do inbox: `open` / `connecting` / `close` |
| **Alerta** | `CONNECTION_UPDATE` com `close` → notificação agentes (opcional) |

---

## 19. Proxy

| Decisão | Valor |
|---------|-------|
| **Fase** | **Fase 1** — seção opcional no wizard; aba settings na Fase 2 |
| **API** | `POST /proxy/set/:instanceName` com body `host`/`port`/`protocol` (runtime) |
| **Create inline** | `proxyHost` em `POST /instance/create` quando preenchido no wizard |
| **Default** | `proxy_enabled: false` |
| **Validação** | Tratar HTTP 400 `Invalid proxy` — bloquear avanço ao QR |
| **Pós-alteração** | Sugerir `restart` instância |
| **Global `.env`** | `PROXY_*` no servidor Evolution — não duplicar no `provider_config` |
| **Segurança** | `proxy_password` write-only — [§15](#15-segredos-no-provider_config) |

Ver [business-rules-adaptation.md § Proxy](./business-rules-adaptation.md#proxy--decisão-de-negócio-incluir-na-fase-1).

---

## 20. Defaults das regras (fork ≠ Evolution Manager)

| Decisão | Valor |
|---------|-------|
| **Fonte de verdade** | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| **`sign_msg`** | **`false`** (Manager Evolution default ON — fork OFF: CW já mostra agente) |
| **`groups_ignore`** | **`true`** (Manager screenshot OFF — fork ON: suporte 1:1) |
| **`reopen_conversation`** | **`true`** — **Fase 1** (comportamento inbound) |
| **`conversation_pending`** | **`false`** (CW default open) |
| **`merge_brazil_contacts`** | **`true`** (fork BR) |
| **import_*** | **`false`**, `days_limit_import_messages: 7` (Manager UI, não API 60) |
| **Regras não portadas** | `autoCreate`, bot 123456, `organization`/`logo`, SQL import, `WAID:` |

Wizard e factories devem aplicar o JSON de defaults do documento de adaptação — não copiar defaults do `instance.controller.ts` Evolution.

---

## Histórico

| Data | Decisão |
|------|---------|
| jun/2026 | Documento criado; rota B, auth apikey, sendText com fallback |
| jun/2026 | MVP enxuto, batch data, ADR job, ActionCable, segredos, FRONTEND_URL |
| jun/2026 | Proxy Fase 1; defaults fork; business-rules-adaptation.md |
