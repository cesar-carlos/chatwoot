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
| 2 | `MessageForwardModal` (preview, recentes, busca, multi-select) | ✅ |
| 3 | Wire context menu + `Message.vue` | ✅ |
| 4 | Badge em `Base.vue` | ✅ |
| 5 | Docs ADR §34 + checklist + esta pasta | ✅ |
| 6 | Endpoint custom (fallback) | ⏸️ não necessário |

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
  message: sourceContent,
  private: false,
  contentAttributes: {
    forwarded: true,
    forwarded_from_message_id,
    forwarded_from_conversation_id
  },
  echo_id: uuid,
  files: File[] // baixados dos attachments da origem
}
```

→ `MessageApi.create` → `Messages::MessageBuilder` → `SendReplyJob`.

### 4. Loop

- Sequencial até `MAX_FORWARD_DESTINATIONS`
- Falha em um destino **não** aborta os demais
- Retorno `{ succeeded, failed, errors }`

### 5. Fork conventions

| Preferir | Uso |
|----------|-----|
| `custom/` | Composable + modal |
| `// FORK:` fino | Menu, options, badge |
| Sem | Novo controller/rota no MVP; editar MessageBuilder |

---

## Mapa de arquivos

| Path | Tipo |
|------|------|
| `custom/app/javascript/dashboard/composables/useMessageForward.js` | novo |
| `custom/app/javascript/dashboard/components/forward/MessageForwardModal.vue` | novo |
| `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` | FORK |
| `app/javascript/dashboard/components-next/message/Message.vue` | FORK |
| `app/javascript/dashboard/components-next/message/bubbles/Base.vue` | FORK |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | EN |
| `doc/feature/whatsapp-provider/evolution-go/decisions.md` | ADR §34 |
| `doc/feature/message-forward/*` | esta feature |

Commit de referência: `d3c7d3c61` (`feat(fork): add WhatsApp-like message forward in Chatwoot`).

---

## Critérios de aceite

- [x] Forward só em inbox Evolution com conteúdo ou anexo
- [x] Modal: recentes + busca + multi-select ≤ 5 + preview
- [x] Texto/mídia saem pelo pipeline normal de outbound
- [x] Badge “Forwarded” no CW destino
- [x] Erro parcial reportado
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

MVP sem suite dedicada (regra: specs sob demanda). Smoke manual:

1. Inbox `evolution_go` — encaminhar texto para conversa recente
2. Encaminhar imagem para contato buscado (cria conversa se preciso)
3. Selecionar 2 destinos — ambos recebem
4. Destino open de outro agente / fora de escopo — toast com mensagem 422 (não 401 genérico)
5. Badge visível na bolha outgoing encaminhada
6. Custom role com `conversation_reply_assigned_only`: encaminhar para conversa resolved/unassigned no escopo → reopen+assign e envia
7. Grupo WhatsApp (`@g.us`) no mesmo inbox — prepare via contactable reusando CI, depois envia
8. Com `lock_to_single_conversation` false e vários threads — `conversation_id` do modal reabre o chat escolhido

---

*Última atualização: 13/ago/2026*
