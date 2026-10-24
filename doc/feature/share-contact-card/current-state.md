# Share Contact Card — Estado Atual

Inventário do contact card compartilhado: inbound original e outbound implementado.

---

## Inbound

### WhatsApp

| Item | Local |
|------|-------|
| Detecção `type: contacts` | `app/services/whatsapp/incoming_message_base_service.rb` |
| Uma mensagem por contato | `create_contact_messages` |
| Attachment `contact` | `attach_contact` — `fallback_title` = telefone, `meta` = `firstName` / `lastName` |
| Spec | `spec/services/whatsapp/incoming_message_service_spec.rb` |

### Telegram

| Item | Local |
|------|-------|
| Detecção `message.contact` | `app/services/telegram/incoming_message_service.rb` |
| Attachment `contact` | `attach_contact` — `fallback_title` = `phone_number`, `meta` = `first_name` / `last_name` |
| Spec | `spec/services/telegram/incoming_message_service_spec.rb` |

---

## Modelo

`Attachment` `file_type: contact` (`8`) está em `NON_FILE_TYPES`: não exige blob.

| Campo | Outbound | Inbound |
|-------|----------|---------|
| `fallback_title` | Telefone E.164 | Telefone recebido |
| `meta.firstName` / `meta.lastName` | Nome partido no primeiro espaço | WhatsApp grava camelCase |
| `meta.first_name` / `meta.last_name` | Lidos como fallback | Telegram grava snake_case |
| `meta.companyName` | `additional_attributes.company_name` ou `contact.company.name` | Não usado no inbound |

`message.content` fica vazio. A lista de conversas usa o attachment.

---

## Outbound

`Custom::Messages::MessageBuilder` chama `Custom::Messages::SharedContactHandler` no início de `process_attachments`.

Contrato:

```json
POST /api/v1/accounts/:account_id/conversations/:id/messages
{ "shared_contact_id": 123 }
```

O handler rejeita a mensagem quando:

- o contato não existe, não tem telefone, ou o telefone não é um E.164 válido
- o canal não é `Channel::Whatsapp` nem `Channel::Telegram`
- o payload traz arquivo, `content` ou `private: true`
- há `user` e ele não tem `administrator`, `agent` nem `contact_manage`

Sem `user` (chamada interna), a checagem de permissão não roda. A capability olha só a classe do canal: qualquer `Channel::Whatsapp` passa, e o provider concreto faz o envio.

### Canais

| Canal | Inbound | Outbound | Envio |
|-------|---------|----------|-------|
| WhatsApp Cloud | Sim | Sim | `Whatsapp::ContactDelivery` + `type: contacts`, com `context` de reply-to |
| WhatsApp 360dialog | Sim | Sim | Mesmo payload `contacts`, sem `context` (os outros envios desse provider também não citam) |
| Evolution | — | Sim | `sendContact` em `custom/` |
| Evolution Go | — | Sim | vCard em `custom/` |
| Telegram | Sim | Sim | `sendContact`, `business_connection_id` e `reply_to_message_id` |
| API, LINE, Facebook, Instagram, SMS | Não | Não | — |

Payload WhatsApp (`lib/whatsapp/contact_message_payload_builder.rb`):

```json
{
  "type": "contacts",
  "contacts": [{
    "name": {
      "formatted_name": "João Silva",
      "first_name": "João",
      "last_name": "Silva"
    },
    "org": { "company": "Acme" },
    "phones": [{ "phone": "+5511999999999", "type": "CELL" }]
  }]
}
```

`org` só entra quando há empresa. Nome vazio usa o telefone como `formatted_name`. Um único token preenche `first_name` e omite `last_name`.

Evolution mapeia isso para `fullName`, `phoneNumber` e `organization`. Evolution Go monta o vCard com os mesmos campos.

### Arquivos

| Peça | Arquivo |
|------|---------|
| Handler | `custom/app/services/custom/messages/shared_contact_handler.rb` |
| Gancho no builder | `custom/app/builders/custom/messages/message_builder.rb` |
| Capability | `custom/lib/channel_capabilities/share_contact.rb` |
| Payload WhatsApp | `lib/whatsapp/contact_message_payload_builder.rb` |
| Entrega Cloud / 360dialog | `lib/whatsapp/contact_delivery.rb` |
| Telegram | `app/services/telegram/send_attachments_service.rb` |
| Evolution / Evolution Go | `custom/app/services/custom/whatsapp/providers/` |
| API do dashboard | `app/javascript/dashboard/api/inbox/message.js` |
| Pending message | `app/javascript/dashboard/helper/commons.js` (`normalizeSharePhone`) |

### Specs

| Spec | Cobre |
|------|-------|
| `spec/custom/services/custom/messages/shared_contact_handler_spec.rb` | Attachment, E.164, empresa, erros e permissão |
| `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb` | `type: contacts` |
| `spec/services/whatsapp/providers/whatsapp360_dialog_service_spec.rb` | `type: contacts` + `org` |
| `spec/services/telegram/send_attachments_service_spec.rb` | `sendContact` e `business_connection_id` |
| `spec/custom/.../evolution_service_spec.rb` | `sendContact` |
| `spec/custom/.../evolution_go/api_client_spec.rb` | cliente `send_contact` |
| `ShareContactForm.spec.js` | Atalho, `type="button"`, contato sem telefone |

---

## Frontend

| Peça | Comportamento |
|------|----------------|
| `ReplyBottomPanel.vue` | Botão `i-ph-address-book` |
| `ReplyBox.vue` | Visibilidade, envio e `CONVERSATION_EVENTS.SHARED_CONTACT` |
| `ShareContact/ShareContactDialog.vue` | `Dialog` `md` |
| `ShareContact/ShareContactForm.vue` | Atalho, busca e contato sem telefone |
| `bubbles/Contact.vue` | Sem "Salvar contato" no outgoing; lê camelCase e snake_case; copy `CONTACT_OUTGOING` |
| `useMessagePreview.js` | Lista mostra `CHAT_LIST.ATTACHMENTS.contact.CONTENT` e `i-lucide-contact` mesmo com `content` |

O pending message parte o nome em `firstName` / `lastName` e normaliza o telefone no cliente antes da API responder. Empresa não entra no preview otimista; o bubble também não exibe empresa.

### Botão

Oculto quando a nota é privada, o editor está desabilitado, o canal não é suportado, ou o agente não tem `administrator`, `agent` nem `contact_manage`.

| Canal | Regra |
|-------|--------|
| Telegram | Visível |
| Evolution e Evolution Go | Visível, sem janela de 24h |
| Cloud e 360dialog | Visível só com `can_reply` |
| Demais | Oculto |

`DISABLED_SESSION_EXPIRED` existe no i18n e não é usada: o botão some em vez de ficar desabilitado.

### Atalho da conversa

O card aparece sempre que a conversa tem contato.

- Com telefone: botão "Compartilhar" com `type="button"`, para não submeter o `<form>` do `Dialog` junto.
- Sem telefone: texto `NO_PHONE_CURRENT` e link interno para `/app/accounts/:id/contacts/:id`.

A busca esconde contatos sem telefone. Se a API devolver só contatos sem telefone, o empty state é `NO_PHONE`.

---

## Nomes que não são esta feature

| Nome | Significado |
|------|-------------|
| `ContactsCard.vue` | Card da lista de contatos do CRM |
| `Contact.vue` (bubble) | Cartão compartilhado na conversa |
| `Contact` (model) | Contato do CRM, fonte do envio |

---

## Ainda aberto

1. Deduplicação de echo de coexistence, se o mesmo `source_id` duplicar.
2. Inbox API, bots e API pública.
3. Vários telefones no mesmo cartão, feature flag, atalho de teclado e aviso ao compartilhar o próprio contato da conversa.
4. Z-API não existe neste fork.

Detalhe em [improvements-backlog.md](./improvements-backlog.md).

---

*Ver [ui-design.md](./ui-design.md) para a UI e [implementation-decision-tree.md](./implementation-decision-tree.md) para as decisões.*
