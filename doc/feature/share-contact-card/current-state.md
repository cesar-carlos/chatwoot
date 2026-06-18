# Share Contact Card — Estado Atual

Inventário do que já existe no codebase para **contact card compartilhado** (inbound + outbound MVP).

---

## O que já funciona (inbound)

### WhatsApp

| Item | Local |
|------|-------|
| Detecção `type: contacts` | `app/services/whatsapp/incoming_message_base_service.rb` |
| Criação de mensagem por contato | `create_contact_messages` |
| Attachment `contact` | `attach_contact` — `fallback_title` = telefone, `meta` = firstName/lastName |
| Spec | `spec/services/whatsapp/incoming_message_service_spec.rb` (context `valid contact message params`) |

Payload inbound relevante:

```ruby
# message['contacts'] => array de contatos
# cada contato: name (formatted_name, first_name, last_name), phones [{ phone: '+...' }]
```

### Telegram

| Item | Local |
|------|-------|
| Detecção `message.contact` | `app/services/telegram/incoming_message_service.rb` |
| Attachment `contact` | `attach_contact` — `fallback_title` = phone_number, `meta` = first_name/last_name |
| Spec | `spec/services/telegram/incoming_message_service_spec.rb` (context `valid contact message params`) |

---

## Modelo de dados

### `Attachment`

```ruby
# app/models/attachment.rb
enum file_type: { ..., contact: 8, ... }

def contact_metadata
  { fallback_title: fallback_title, meta: meta || {} }
end
```

- Contact attachments **não exigem** `has_one_attached :file` (estão em `NON_FILE_TYPES`).
- `with_attached_file?` retorna `false` para `contact`.

### Metadados usados na UI

| Campo | Origem inbound | Uso no frontend |
|-------|----------------|-----------------|
| `fallback_title` | Telefone | `Contact.vue` → `phoneNumber` |
| `meta.firstName` / `meta.first_name` | Nome | `Contact.vue` → `contactName` |
| `meta.lastName` / `meta.last_name` | Sobrenome | `Contact.vue` → `contactName` |

**Nota:** WhatsApp inbound grava `firstName`/`lastName` (camelCase); Telegram inbound grava `first_name`/`last_name` (snake_case). O bubble já trata camelCase; normalizar no outbound.

---

## Frontend (exibição)

| Componente | Função |
|------------|--------|
| `components-next/message/bubbles/Contact.vue` | Card visual; Save Contact só em incoming |
| `components-next/message/Message.vue` | Roteia `ATTACHMENT_TYPES.CONTACT` → `ContactBubble` |
| `components-next/message/constants.js` | `CONTACT` em `ATTACHMENT_TYPES` e `NON_FILE_TYPES` |
| `ConversationCard/MessagePreview.vue` | Preview “Shared contact” na lista |
| i18n | `CONVERSATION.SHARED_ATTACHMENT.CONTACT`, `CHAT_LIST.ATTACHMENTS.contact.CONTENT` |

### “Save Contact” (já implementado)

`Contact.vue` permite ao agente:

1. Buscar contato existente por telefone (`contacts/filter`)
2. Criar novo contato se não existir (`contacts/create`)
3. Abrir aba do contato no CRM

Isso **não** envia o card — apenas persiste no CRM um contato recebido do cliente.

---

## Outbound (implementado)

### Outbound por canal

| Canal | Inbound contact | Outbound contact | Observação |
|-------|-----------------|------------------|------------|
| WhatsApp Cloud | ✅ | ✅ | `type: contacts` via `Whatsapp::ContactDelivery` |
| WhatsApp 360dialog | ✅ | ✅ | Mesmo payload contacts |
| Telegram | ✅ | ✅ | `sendContact` + `business_connection_id` |
| LINE | ❌ | ❌ | — |
| Facebook / Instagram | ❌ | ❌ | — |
| SMS / Twilio | ❌ | ❌ | — |
| API Inbox | ❌ | ❌ | — |

### API / MessageBuilder

- `shared_contact_id` na API de mensagens (`POST .../messages`)
- `Custom::Messages::SharedContactHandler` cria attachment `contact` (via prepend em `MessageBuilder`)
- `ChannelCapabilities::ShareContact` valida WhatsApp + Telegram

### UI ReplyBox

- `widgets/conversation/ShareContact/ShareContactDialog.vue` + `ShareContactForm.vue`
- Botão `i-ph-address-book` em `ReplyBottomPanel` (guard `can_reply` no WhatsApp)

### Fork `custom/`

- `custom/lib/channel_capabilities/share_contact.rb`
- `custom/app/services/custom/messages/shared_contact_handler.rb`
- `custom/app/builders/custom/messages/message_builder.rb` (prepend `perform`)

---

## Confusão de nomenclatura (evitar)

| Nome no código | Significado |
|----------------|-------------|
| `ContactsCard.vue` | Card da **lista de contatos** no CRM — **não** é contact card de mensagem |
| `Contact.vue` (bubble) | Card de contato **compartilhado em conversa** |
| `Contact` (model) | Entidade CRM — fonte de dados para envio outbound |

---

## APIs externas relevantes (outbound)

### WhatsApp Cloud API

```json
{
  "messaging_product": "whatsapp",
  "to": "<phone>",
  "type": "contacts",
  "contacts": [{
    "name": { "formatted_name": "...", "first_name": "...", "last_name": "..." },
    "phones": [{ "phone": "+...", "type": "CELL" }]
  }]
}
```

Ref: [WhatsApp Cloud — contacts messages](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/contacts-messages)

### Telegram Bot API

```
POST /sendContact
{ "chat_id": "...", "phone_number": "+...", "first_name": "...", "last_name": "..." }
```

Ref: [Telegram sendContact](https://core.telegram.org/bots/api#sendcontact)

---

## Lacunas restantes (pós-MVP)

1. **Gateways** Evolution/Z-API — Fase 5 em `custom/`
2. **Echo dedup** — follow-up se duplicar `source_id`
3. **Specs automatizados** — P1 no backlog

---

## Padrões de UI existentes para reuso (outbound)

O plano de UI em [ui-design.md](./ui-design.md) mapeia componentes já usados no projeto:

| Necessidade | Componente existente |
|-------------|---------------------|
| Botão na barra do ReplyBox | `ReplyBottomPanel.vue` — `NextButton` slate faded sm |
| Modal | `components-next/dialog/Dialog.vue` |
| Busca de contatos | `ComboBox` + `createContactSearcher()` |
| Card visual de contato | Layout de `ContactMergeForm.vue` |
| Resultado na conversa | `bubbles/Contact.vue` (sem novo bubble) |
| Melhorias MVP / backlog | [improvements-backlog.md](./improvements-backlog.md) |

---

*Ver [implementation-decision-tree.md](./implementation-decision-tree.md) para decisões e [implementation-plan.md](./implementation-plan.md) para fases.*
