# Diferenças vs WhatsApp Cloud API oficial

O provider `evolution` usa **Baileys** (WhatsApp Web) — não a Graph API / WABA. Implicações para o fork Chatwoot.

**Contexto geral:** [../official-vs-unofficial-restrictions.md](../official-vs-unofficial-restrictions.md)

---

## O que deixa de existir (Meta)

| Regra / feature Cloud | Provider `evolution` | Ação no fork |
|----------------------|----------------------|--------------|
| Janela 24h Meta | Não existe | Prepend `MessageWindowService` → `nil` |
| Templates WABA obrigatórios | Não existe | `sync_templates` noop; `send_template` → texto livre |
| Embedded signup | Não existe | Wizard próprio (QR) |
| `phone_number_id` / `business_account_id` | Não existe | `instance_name` + `api_key` |
| HMAC webhook Meta | Não existe | Auth `apikey` / token URL |
| Calling API Meta (voz EE) | Não existe | Projeto voz separado |
| Campanhas one-off | Cloud only | Indisponível — OK |
| CSAT template cloud | Cloud only | Indisponível — OK |
| Health management cloud | Cloud only | `connectionState` Evolution |

---

## O que o Chatwoot ainda impõe (e precisa bypass)

Mesmo sem Cloud API, o código Chatwoot força regras em **todo** `Channel::Whatsapp`:

### Janela 24h

```ruby
# app/services/conversations/message_window_service.rb
when 'Channel::Whatsapp'
  MESSAGING_WINDOW_24_HOURS
```

**Mitigação:** prepend retorna `nil` quando `provider == 'evolution'`.

### Template forçado no envio

```ruby
# app/services/whatsapp/send_on_whatsapp_service.rb
should_send_template_message = template_params.present? || !message.conversation.can_reply?
```

Com janela bypass, `can_reply?` fica `true` — envio texto livre funciona.

### `process_response` formato Meta

```ruby
# BaseService — espera parsed_response['messages'].first['id']
```

**Mitigação:** override em `EvolutionService`:

```ruby
def process_response(response)
  parsed = response.parsed_response
  return parsed.dig('key', 'id') if response.success? && parsed['key'].present?
  # fallback error handling
end
```

---

## O que ganha com gateway/Baileys

| Benefício | Notas |
|-----------|-------|
| Texto livre anytime | Principal motivador do provider |
| Sem aprovação de template | Copy dinâmico, bots, IA |
| Grupos (se não ignorados) | `groups_ignore: false` — UX diferente do cloud |
| QR / self-host | Controle da instância Evolution |
| Proxy por inbox | `POST /proxy/set` |

---

## Riscos que permanecem

| Risco | Mitigação operacional |
|-------|----------------------|
| ToS WhatsApp | Aceitar risco; não prometer compliance Meta |
| Ban de número | Proxy, warm-up, evitar spam |
| Sessão cai (QR expira) | Alertas `CONNECTION_UPDATE`; fluxo reconnect na UI |
| LGPD / retenção | Políticas da conta — igual outros canais |
| Instabilidade Baileys | Monitorar `connectionState`; versão Evolution fixa |

---

## Frontend — gates por provider

Ocultar para `evolution` (mesmo tratamento que gateway genérico):

| Feature UI | Helper atual | Evolution |
|------------|--------------|-----------|
| Seletor templates WABA | `isAWhatsAppCloudChannel` | Ocultar |
| Campanhas WhatsApp | cloud only | Ocultar |
| Voice PTT cloud | cloud only | Ocultar |
| Embedded signup | cloud only | N/A — wizard QR |
| Health cloud | cloud only | Substituir por status Evolution |

Adicionar: `isEvolutionWhatsAppChannel` ou entry em `messagingProviderCapabilities.js`.

---

## Templates no Chatwoot

| Cenário | Comportamento |
|---------|---------------|
| Agente escolhe template no ReplyBox | Não mostrar seletor WABA |
| Automação envia `template_params` | `EvolutionService#send_template` → renderizar como texto ou noop com log |
| `sync_templates` job | Noop para `evolution` |

---

## Identificadores de contato

| Cloud API | Evolution / Baileys |
|-----------|---------------------|
| `wa_id` estável | Telefone ou LID (`@lid` + `remoteJidAlt`) |
| BSUID (futuro Meta) | Não aplicável |

Normalizer deve:

1. Preferir dígitos de `remoteJidAlt` quando `addressingMode == 'lid'`
2. Aplicar `merge_brazil_contacts` (+55 com/sem 9º dígito) se habilitado
3. Usar `key.id` como `source_id` da mensagem

---

## Coexistência com integração Evolution→Chatwoot

| Cenário | Permitido? |
|---------|------------|
| Mesma conta CW, inbox `api` (Evolution SDK) + inbox `evolution` provider | Sim, se instâncias Evolution **diferentes** |
| Mesma instância Evolution com Chatwoot integration ON + webhook para CW provider | **Não** — duplica mensagens |
| Mesmo número em dois inboxes `Channel::Whatsapp` | **Não** — `phone_number` unique |

---

## Comparativo rápido

| | `whatsapp_cloud` | `default` (360dialog) | `evolution` |
|--|------------------|----------------------|-------------|
| Oficial Meta | Sim | Sim (BSP) | Não |
| Bot / Baileys | Não | Não | Sim |
| Templates WABA | Sim | Sim | Não |
| Janela 24h | Sim | Sim | **Bypass** |
| QR connect | Não | Não | Sim |
| Proxy | Não | Não | Sim |
| Grupos | Não | Não | Configurável |
