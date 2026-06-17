# Share Contact Card — Estado Atual

Inventário do que já existe no codebase para **contact card compartilhado** e o que falta para **envio pelo agente**.

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
| `components-next/message/bubbles/Contact.vue` | Card visual + botão “Save Contact” |
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

## O que não existe (outbound)

### Envio por canal

| Canal | Inbound contact | Outbound contact | Observação |
|-------|-----------------|------------------|------------|
| WhatsApp Cloud | ✅ | ❌ | `send_attachment_message` só image/audio/video/document |
| WhatsApp 360dialog | ✅ | ❌ | Mesmo padrão |
| Telegram | ✅ | ❌ | `SendAttachmentsService` não trata `contact` |
| LINE | ❌ | ❌ | — |
| Facebook / Instagram | ❌ | ❌ | — |
| SMS / Twilio | ❌ | ❌ | — |
| API Inbox | ❌ | ❌ | — |

### API / MessageBuilder

- `Messages::MessageBuilder#process_attachments` só aceita uploads (`file` / `signed_id`).
- Não há parâmetro `shared_contact_id` nem criação programática de attachment `contact`.
- `ReplyBox` não oferece ação “compartilhar contato do CRM”.

### Fork `custom/`

- Nenhuma implementação adicional para contact card em `custom/`.

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

## Lacunas que bloqueiam MVP outbound

1. **MessageBuilder** — criar attachment `contact` sem upload de arquivo
2. **Send services** — ramo `contact` em WhatsApp providers e Telegram
3. **Frontend** — picker de contato + fluxo de envio no `ReplyBox`
4. **Validação** — contato compartilhado precisa ter `phone_number` (obrigatório nos canais)
5. **Normalização de meta** — padronizar camelCase no outbound para consistência com bubble
6. **Gateway providers** (Evolution etc.) — adapter em `custom/` se o fork usar providers não oficiais

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
