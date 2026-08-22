# Message Forward — Plano de implementação (as-built)

Documento **as-built** do MVP entregue em 16/jul/2026. Fonte normativa para manutenção; decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Permitir que o agente encaminhe texto e/ou mídia de uma mensagem para até 5 conversas/contatos do **mesmo** inbox WhatsApp Evolution, com UX de modal + badge no dashboard, **sem** depender de API Go de forward.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Composable `useMessageForward` + i18n EN | ✅ |
| 2 | `MessageForwardModal` (preview, caption, recentes, busca, multi-select) | ✅ |
| 3 | Wire context menu + `Message.vue` | ✅ |
| 4 | Badge em `Base.vue` | ✅ |
| 5 | Docs ADR §34 + checklist + esta pasta | ✅ |
| 6 | Endpoint custom (fallback) | ⏸️ não necessário |
| 7 | Clone server-side + i18n pt_BR + overlay `MessageBuilder` via `super` | ✅ |
| 8 | Multi-select timeline + polish UX (progresso, toast Open, Retry, Shift+clique) | ✅ |
| 9 | Polish UI (Checkbox design system, modal `xl`, barra compacta) | ✅ |
| 10 | Layout do modal: Dialog `max-h-[90vh]`, lista `flex-1 overflow-y-auto`, Tailwind scan `custom/`, busca alinhada | ✅ |

---

## Detalhe técnico

### 1. Gate

```js
inboxSupportsForward(inbox) // Channel::Whatsapp + evolution_go|evolution
messageCanBeForwarded(message) // content || attachments.length
```

### 2. Resolve destino

Sempre `getContactableInboxes` → `ConversationApi.create` (`AgentStartService`), **mesmo** quando o modal já tem `conversationId`:

- contactable overlay reusa `contact_inbox` existente (grupos `@g.us`, LID) em vez de exigir telefone
- modal envia `conversation_id` (`display_id`) quando o destino veio de recentes; `AgentStartService` só honra se for do mesmo `contact_inbox`
- sem conversa → cria + assignee = agente
- resolved/snoozed → reopen + assign
- open/pending atribuída a outro → **422** `OpenAssignedToOtherAgent`
- open/pending fora de `show?` → **422** `OutsidePermissionScope`
- open/pending no escopo → assign ao iniciador (inclusive se auto-assign roubar após `open!`), depois `messages#create`

Não reutilizar `destination.conversationId` para `POST …/messages` direto: custom role com `conversation_reply_assigned_only` responde **401** (`reply?`) se o agente ainda não for assignee.

### 3. Payload de envio

```js
{
  conversationId,
  message: captionOrSourceContent,
  private: false,
  contentAttributes: {
    forwarded: true,
    forwarded_from_message_id,
    forwarded_from_conversation_id
  },
  echo_id: uuid,
  attachment_ids: [/* ids da origem quando todos têm id */],
  files: File[] // fallback: fetch browser se algum anexo não tiver id
}
```

→ `MessageApi.create` → `Custom::Messages::MessageBuilder` (`merge_cloned_attachment_blobs!` + `super`) → `SendReplyJob`.

Clone server-side **exige** `forwarded_from_message_id`; sem ele, `attachment_ids` é ignorado (não clona blobs arbitrários da account).

### 4. Loop

- Destinos sequenciais até `MAX_FORWARD_DESTINATIONS`
- Por destino: prepare 1×, depois cada mensagem em ordem (`created_at` / `id`), até `MAX_FORWARD_MESSAGES`
- Falha em uma mensagem **não** aborta as seguintes daquele destino; o destino conta como falha se qualquer envio falhar
- Falha em um destino **não** aborta os demais
- `onProgress` alimenta `SENDING_PROGRESS` no modal
- Retorno `{ succeeded, failed, errors, succeededConversationIds }`

### 5. Fork conventions

| Preferir | Uso |
|----------|-----|
| `custom/` | Composable + modal + `AttachmentCloneService` |
| `prepend_mod_with` | `MessageBuilder` (hooks + `super`, sem copiar `#perform` OSS) e contactable |
| `// FORK:` fino | Menu, options, badge, `MessageList.vue` (`setTimeline`), `message.js`, `Dialog.vue` (max-h), `tailwind.config.js` (`content`) |
| Sem | Novo controller/rota |

---

## Mapa de arquivos

| Path | Tipo |
|------|------|
| `custom/app/javascript/dashboard/composables/useMessageForward.js` | novo |
| `custom/app/javascript/dashboard/composables/useMessageForwardSelection.js` | novo |
| `custom/app/javascript/dashboard/components/forward/MessageForwardModal.vue` | novo |
| `custom/app/javascript/dashboard/components/forward/MessageForwardDestinationRow.vue` | novo |
| `custom/app/javascript/dashboard/components/forward/MessageForwardSelectionBar.vue` | novo |
| `custom/app/services/custom/messages/attachment_clone_service.rb` | novo |
| `custom/app/services/custom/contacts/contactable_inboxes_service.rb` | overlay |
| `custom/app/builders/custom/messages/message_builder.rb` | overlay (`super`) |
| `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` | FORK |
| `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` | FORK |
| `app/javascript/dashboard/components-next/message/Message.vue` | FORK |
| `app/javascript/dashboard/components-next/message/MessageList.vue` | FORK |
| `app/javascript/dashboard/components-next/message/bubbles/Base.vue` | FORK |
| `app/javascript/dashboard/api/inbox/message.js` | FORK |
| `app/javascript/dashboard/components-next/dialog/Dialog.vue` | FORK (max-h + overflow no slot) |
| `tailwind.config.js` | FORK (`content` → `custom/app/javascript/**`) |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | EN |
| `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` | pt_BR (fork) |
| `doc/feature/whatsapp-provider/evolution-go/decisions.md` | ADR §34 |
| `doc/feature/message-forward/*` | esta feature |

Commit de referência: `d3c7d3c61` (`feat(fork): add WhatsApp-like message forward in Chatwoot`).

---

## Critérios de aceite

- [x] Forward só em inbox Evolution com conteúdo ou anexo
- [x] Modal: recentes + busca + destinos ≤ 5 + preview + caption (1 msg)
- [x] Lista de destinos com scroll interno (`flex-1 overflow-y-auto`); footer Cancelar/Encaminhar sempre visível
- [x] Campo de busca: lupa e texto no mesmo outline (`type="text"`, não `search`)
- [x] Multi-select na timeline ≤ 10, barra no lugar do composer, envio em ordem
- [x] Select permanece ativo ao desmarcar; sai só no ✕ / Escape / sucesso
- [x] Toast Open conversation (1 destino); Retry nos destinos que falharam
- [x] Shift+clique no intervalo; continue-on-fail por mensagem no destino
- [x] Texto/mídia saem pelo pipeline normal de outbound
- [x] Badge “Forwarded” no CW destino
- [x] Erro parcial reportado (i18n EN + pt_BR)
- [x] Sem navegação forçada pós-envio
- [ ] E2E operador (checklist Go) — pendente validação manual

Checklist operacional: [evolution-go/validation-checklist.md](../whatsapp-provider/evolution-go/validation-checklist.md).

---

## Deploy

Após merge:

```bash
RAILS_ENV=production NODE_ENV=production bundle exec rails assets:precompile
pm2 restart chatwoot-web chatwoot-worker
```

Hard refresh no browser para carregar o bundle Vite novo.

---

## Testes

Smoke manual:

1. Inbox `evolution_go` — encaminhar texto para conversa recente
2. Encaminhar imagem para contato buscado (cria conversa se preciso)
3. Selecionar 2 destinos — ambos recebem
4. Destino open de outro agente / fora de escopo — toast com mensagem 422 (não 401 genérico)
5. Badge visível na bolha outgoing encaminhada
6. Custom role com `conversation_reply_assigned_only`: encaminhar para conversa resolved/unassigned no escopo → reopen+assign e envia
7. Grupo WhatsApp (`@g.us`) no mesmo inbox — prepare via contactable reusando CI, depois envia
8. Com `lock_to_single_conversation` false e vários threads — `conversation_id` do modal reabre o chat escolhido
9. Modal Encaminhar com ~10 recentes: lista tem scrollbar, **Cancelar / Encaminhar** visíveis, lupa alinhada ao campo de busca

Specs de overlay: `spec/custom/services/custom/messages/attachment_clone_service_spec.rb`.

---

*Última atualização: 22/ago/2026*
