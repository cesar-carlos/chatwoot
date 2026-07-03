# Decisões fechadas — Provider Evolution

Decisões de implementação registradas para evitar retrabalho na Fase 0–1. **Status:** aprovadas para o fork (jun/2026).

---

## 1. Rota webhook

| Decisão | Valor |
|---------|-------|
| **Rota** | `POST /webhooks/evolution/:instance_name` |
| **Controller** | `Webhooks::EvolutionController` (`custom/app/controllers/webhooks/evolution_controller.rb`) |
| **Job** | `Webhooks::WhatsappEventsJob` (prepend) |

**Motivo:** o controller upstream (`Webhooks::WhatsappController`) e o job assumem payload Meta/360dialog (`phone_number` na URL ou `object: whatsapp_business_account`). O envelope Evolution (`event`, `instance`, `data`) colide com essa validação.

**URL registrada na Evolution:**

```
https://{FRONTEND_URL}/webhooks/evolution/{instance_name}
```

**Por que `FRONTEND_URL`:** o Chatwoot já monta webhooks de channel com essa variável (`app/models/inbox.rb`, `Whatsapp::WebhookSetupService`, `Whatsapp360DialogService`). A Evolution deve usar o mesmo host público que Telegram, SMS e WhatsApp cloud — não `BACKEND_URL` interno.

Configurar em `Provisioner#register_webhook!` (via `ConnectionService#register_webhook!`) com `byEvents: false` (evento único na URL base).

---

## 2. Autenticação do webhook

| Decisão | Valor |
|---------|-------|
| **Método primário** | Validar `apikey` do envelope contra `provider_config.api_key` |
| **Método secundário** | Query `?token=` com `provider_config.webhook_token` (gerado no provision; incluído na URL do webhook) |
| **IP allowlist** | Fora do escopo MVP |

```ruby
# EvolutionController#authenticate_webhook!
def authenticate_webhook!
  @channel = find_channel_by_instance_name
  return head :not_found if @channel.blank?

  return if webhook_token_valid?
  return if apikey_valid?

  head :unauthorized
end
```

Aceita **qualquer um** dos métodos: `?token=` (se `webhook_token` presente) ou `apikey` no body/header.

**Motivo:** Evolution envia `apikey` no body do webhook (`webhook.controller.ts` → `emit()`). Token na URL sozinho não cobre o caso em que a URL vaza sem o secret no query string.

---

## 3. Resolução do channel no job

| Decisão | Valor |
|---------|-------|
| **Lookup** | `Channel::Whatsapp` onde `provider = 'evolution'` e `provider_config->>'instance_name' = :instance_name` |
| **Regra operacional** | **1 instância Evolution = 1 inbox** `provider: 'evolution'` no fork |
| **Multi-account** | Dois accounts Chatwoot **não** devem compartilhar o mesmo `instance_name` apontando para webhooks distintos — colisão de rota |

Índice **único global** no banco — **implementado** (migration fork):

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
| **Sempre** | `chatwoot.enabled = false` — nunca habilitar a integração legada |
| **Desabilitar** | `POST /chatwoot/set` com `enabled: false` após create (schema exige todos os campos) |
| **Verificação** | `Provisioner#ensure_chatwoot_integration_disabled!` — `POST /chatwoot/set` + `GET /chatwoot/find` confirma `enabled: false`; falha o provision se ainda ativo |

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
| **Preferência** | `webhookBase64: false` + `POST /chat/getBase64FromMediaMessage/:instanceName` no download inbound |
| **Alternativa** | `webhookBase64: true` na config do webhook (payloads maiores, menos round-trips) |

---

## 12. Mutex no job (album / concorrência)

| Decisão | Valor |
|---------|-------|
| **Dispatcher** | `WebhookDispatcher` normaliza cada item e chama `MessageMutex.with_lock` antes de `IncomingMessageService` / `PhoneOutgoingSyncService` |
| **Helper compartilhado** | `Custom::Whatsapp::Evolution::MessageMutex` — Redis `WHATSAPP_MESSAGE_MUTEX` (mesma chave do job upstream) |
| **Reconciliação** | `LostMessagesReconciliationService` reutiliza `MessageMutex` — não bypassa dedup outbound |
| **sender_id** | Contato inbound: `messages[0].from`; outbound phone: `key.remoteJid`; mutações: `remoteJid` ou `id` |

O prepend `WhatsappEventsJob` **delega** para `WebhookDispatcher` — não mantém `case params[:event]` inline (ver §16).

```ruby
# Resumo — webhook_dispatcher.rb
def process_message_item(channel, params, data_item)
  # … normalizer …
    with_message_lock(channel, sender_id) do
      Custom::Whatsapp::Evolution::InboundMessageProcessor.process(channel, flat_params)
    end
end

def with_message_lock(channel, sender_id, &)
  Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id, &)
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
| **A** — Prepend `WhatsappEventsJob` + **`WebhookDispatcher`** | Reusa pipeline 360dialog; roteamento isolado em service testável | `InboundMessageProcessor` chama `IncomingMessageService` diretamente (sem `job.send`) | **✅ MVP** |
| **B** — `EvolutionWebhookJob` dedicado | Isolamento total (padrão Wavoip) | Duplica roteamento de status/contacts | Reavaliar se prepend gerar bugs |

Implementar **A** na Fase 0–1. O prepend detecta envelope Evolution, normaliza `event`, resolve channel e chama `WebhookDispatcher#dispatch` — **sem** `case event` inline no job.

Eventos suportados no dispatcher: `MESSAGES_UPSERT`, `MESSAGES_UPDATE`, `MESSAGES_DELETE`, `MESSAGES_EDITED`, `CONTACTS_*`, `CONNECTION_UPDATE`, `QRCODE_UPDATED`. Demais eventos: log `[EVOLUTION] unhandled event=… instance=…` (`instance_name` com fallback `instance`).

Se testes de regressão falharem, migrar para **B** sem mudar normalizer.

---

## 17. QR e eventos de conexão na UI

| Decisão | Valor |
|---------|-------|
| **Componente QR** | `EvolutionQrScanModal.vue` — modal compartilhado (wizard + health) |
| **Composable** | `useEvolutionQrSession.js` — polling, expiry ~45s, `evolution_reconnect` |
| **Canal ActionCable** | `EvolutionConnectionChannel` → `evolution:connection:{inbox_id}` |
| **Eventos** | `qrcode_updated`, `connection_update` |
| **Fallback polling** | **3s** no modal; **5s** em `EvolutionHealthPage` |
| **Wizard pós-create** | Etapa "Abrir leitor de QR" abre modal; `fetchFreshQr` chama reconnect na 1ª abertura |
| **Emitter** | `ConnectionService#handle_event` + broadcast `phone_number` ao conectar |

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
| **`reopen` (conversa resolvida)** | **`inbox.lock_to_single_conversation: true`** — Settings inbox, não `provider_config` |
| **`conversation_pending`** | **`false`** (CW default open) |
| **`merge_brazil_contacts`** | **`true`** (fork BR) |
| **import_*** | **`false`**, `days_limit_import_messages: 7` (Manager UI, não API 60) |
| **Regras não portadas** | `autoCreate`, bot 123456, `organization`/`logo`, SQL import, `WAID:` |

Wizard e factories devem aplicar o JSON de defaults do documento de adaptação — não copiar defaults do `instance.controller.ts` Evolution.

---

## 21. Normalização de nomes de evento (webhook)

| Decisão | Valor |
|---------|-------|
| **Módulo** | `Custom::Whatsapp::Evolution::EventNames.normalize` |
| **Transformação** | `messages.upsert` → `MESSAGES_UPSERT` (`tr('.', '_').upcase`) |
| **Onde** | `EvolutionController#sanitized_job_payload` + prepend `WhatsappEventsJob` (defesa em profundidade) |

Evolution v2.3+ envia eventos em minúsculas com ponto; handlers do fork usam SCREAMING_SNAKE. Sem normalização, jobs terminam em ~5–30ms sem criar mensagens.

---

## 22. `validate_provider_config?` — exige conexão `open`

| Decisão | Valor |
|---------|-------|
| **Regra** | `EvolutionService#validate_provider_config?` retorna `true` só se `connectionState` → `state == 'open'` |
| **Runtime keys** | Updates de `connection_status`, QR, `last_sender` via `update_columns` — **não** disparam validação remota |
| **Skip** | `Channel::Whatsapp#validate_provider_config` pula quando só `ProviderConfig::RUNTIME_KEYS` mudam |

Evita falha de validação enquanto instância está em `connecting` ou aguardando QR.

---

## Histórico

| Data | Decisão |
|------|---------|
| jun/2026 | Documento criado; rota B, auth apikey, sendText com fallback |
| jun/2026 | MVP enxuto, batch data, ADR job, ActionCable, segredos, FRONTEND_URL |
| jun/2026 | Proxy Fase 1; defaults fork; business-rules-adaptation.md |
| jun/2026 | `EventNames` (dotted → SCREAMING_SNAKE); `Provisioner`/`ConnectionEvents` split; `validate_provider_config` exige `open` |
