# Message Forward — Estado atual

Inventário do que existe no codebase após o MVP de **pseudo-forward** (16/jul/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Entrada | Item **Forward** no context menu da mensagem |
| Gate de canal | Inbox WhatsApp com `provider` ∈ `evolution_go`, `evolution` |
| Gate de mensagem | Tem `content` e/ou `attachments`; não privada; não failed/progress/deleted |
| Destinos | Até **5** chats do **mesmo inbox** |
| Recentes | Até **10** conversas do store, ordenadas por `last_activity_at` (não pelo sort da lista) |
| Busca | Contatos com telefone **ou** grupos WhatsApp (`is_whatsapp_group` / `@g.us`); reachability no inbox |
| Texto | Cópia do `content` da origem (caption editável no modal) |
| Mídia | Preferência: `attachment_ids[]` → clone ActiveStorage no servidor; fallback: fetch browser + `toSameOriginActiveStorageUrl` |
| Persistência destino | `MessageApi.create` → `MessageBuilder` (+ clone) → `SendReplyJob` → provider outbound |
| Conversão nova | Se contato sem conversa no inbox: `conversations#create` (sem message) + depois create message |
| Badge dashboard | Chip “Forwarded” quando `content_attributes.forwarded` |
| Feedback | Toasts sucesso / parcial / falha (EN) |
| Navegação | Agente **permanece** na conversa atual após encaminhar |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Endpoint Go `/message/forward` | API não expõe |
| Flag WhatsApp `ContextInfo.Forwarded` | Soft-forward nativo exigiria mudança upstream no Go |
| Rótulo “Encaminhada” no app do cliente | Consequência da limitação acima |
| Multi-select de mensagens na timeline | Fora do MVP |
| Cross-inbox / outros canais | Fora do MVP |
| i18n pt/pt_BR | Regra do fork: só EN |
| Clone server-side de blobs | Feito para anexos com `id` via `attachment_ids` + `AttachmentCloneService`; residual: anexos só com URL externa (sem id / sem AS) |

---

## Modelo de dados

Metadado gravado na mensagem **enviada** (destino):

```json
{
  "forwarded": true,
  "forwarded_from_message_id": 12345,
  "forwarded_from_conversation_id": 678
}
```

- Armazenado em `messages.content_attributes` (jsonb).
- Lido no frontend (camelCase ou snake_case) para o badge em `Base.vue`.

---

## Arquivos no código

### Novos (`custom/`)

| Arquivo | Papel |
|---------|-------|
| `custom/app/javascript/dashboard/composables/useMessageForward.js` | Gate, recentes, busca/grupos, clone via `attachment_ids` ou fetch, loop de create |
| `custom/app/javascript/dashboard/components/forward/MessageForwardModal.vue` | Dialog de destino |
| `custom/app/services/custom/messages/attachment_clone_service.rb` | Clone ActiveStorage blobs por `attachment_ids` |
| `custom/app/builders/custom/messages/message_builder.rb` | Merge de blobs clonados antes de `process_attachments` |

### Thin FORK (upstream)

| Arquivo | Mudança |
|---------|---------|
| `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` | Menu Forward + monta modal |
| `app/javascript/dashboard/components-next/message/Message.vue` | `enabledOptions.forward` + `attachments` no payload do menu |
| `app/javascript/dashboard/components-next/message/bubbles/Base.vue` | Badge Forwarded |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | `CONTEXT_MENU.FORWARD` + `CONVERSATION.FORWARD.*` |
| `app/javascript/dashboard/api/inbox/message.js` | `attachment_ids` no create / FormData |

### APIs reutilizadas (sem rota nova)

| API | Uso |
|-----|-----|
| `POST /api/v1/accounts/:id/conversations/:id/messages` | Enviar cópia |
| `POST /api/v1/accounts/:id/conversations` | Criar conversa se necessário |
| `GET …/contacts/search` | Busca no modal |
| `GET …/contacts/:id/conversations` | Achar conversa existente no inbox |
| `GET …/contacts/:id/contactable_inboxes` | `source_id` para create |

---

## Constantes

| Constante | Valor | Arquivo |
|-----------|-------|---------|
| `FORWARD_PROVIDERS` | `evolution_go`, `evolution` | `useMessageForward.js` |
| `MAX_FORWARD_DESTINATIONS` | `5` | idem |
| `MAX_RECENT_CONVERSATIONS` | `10` | idem |
| `MAX_CONTACTABLE_CHECKS` | `20` | idem |

---

## Docs relacionadas

- ADR: [evolution-go/decisions.md §34](../whatsapp-provider/evolution-go/decisions.md)
- Status provider: [evolution-go/status.md](../whatsapp-provider/evolution-go/status.md)
- Checklist: [evolution-go/validation-checklist.md](../whatsapp-provider/evolution-go/validation-checklist.md)

---

*Última atualização: 28/jul/2026*
