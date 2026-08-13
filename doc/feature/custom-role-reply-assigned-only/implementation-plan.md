# Custom Role — Reply Only When Assigned

## Context

Permissões `conversation_*` controlam **visibilidade** (listar/abrir). Um agente com `conversation_team_unassigned_manage` pode ver “Não atribuídas”, abrir a conversa e **já responder**. O banner em `ReplyBoxBanner` só sugere auto-atribuição ao digitar; não bloqueia o envio.

`can_reply` / `isEditorDisabled` tratam janela WhatsApp/API, não assignee. A API `messages#create` autoriza só `show?`.

## Objective

Introduzir a permissão `conversation_reply_assigned_only` ponta a ponta:

1. Checkbox no cadastro de custom role (**desmarcado por padrão**)
2. Com regra ativa: ReplyBox desabilitado se `assignee ≠ current user`
3. Gate na API de create de mensagem (e retry público)
4. Documentação e aceite manual

## Decisões fechadas

- **Permissão:** `conversation_reply_assigned_only`
- **Semântica:** presente = restringe (só responde se atribuída ao agente)
- **Default:** desmarcada — zero mudança no comportamento atual
- **Migração / grant:** não (opt-in explícito; diferente de `inbox_view_manage`)
- **Composer:** desabilita tudo (Responder + Mensagem Privada)
- **Sem custom role:** `administrator` e `agent` sem restrição
- **AgentBot / automations:** sem restrição (`reply?` true / user nil no MessageBuilder)
- **Independente** da hierarquia `conversation_*` (combina com qualquer escopo de visão)
- **i18n:** só `en` + `pt_BR` (exceção fork)
- **Marcador FORK:** `custom role reply assigned only`
- **API unauthorized:** status `401` via `handle_with_exception` (padrão do projeto)

## Access Semantics

| Perfil / estado | Pode responder? |
|-----------------|-----------------|
| Administrator | Sim |
| Agent sem custom role | Sim |
| Custom role **sem** a permissão | Sim (atual) |
| Custom role **com** a permissão + assignee = eu | Sim |
| Custom role **com** a permissão + não atribuída / outro agente | Não (UI desabilitada + API 401) |

Visibilidade de lista/abrir **não muda** — continua regida por `conversation_*` + inbox.

## Architecture (Fork)

| Camada | Arquivo | Papel |
|--------|---------|-------|
| Permissão | `enterprise/app/models/custom_role.rb` | `PERMISSIONS` + `# FORK:` |
| Policy fork | `custom/app/policies/custom/conversation_policy.rb` | `reply?` |
| MessageBuilder | `custom/app/builders/custom/messages/message_builder.rb` | Gate central (API, macros, create+message) |
| API fork | `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` | `authorize(..., :reply?)` + re-raise Pundit; react/edit |
| Macros | `custom/app/services/custom/macros/execution_service.rb` | Skip actions com log quando NotAuthorized |
| FE constants | `app/javascript/dashboard/constants/permissions.js` | Registry + constante |
| FE helper | `app/javascript/dashboard/helper/permissionsHelper.js` | `hasReplyAssignedOnlyRestriction` |
| FE ReplyBox | `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` | `isEditorDisabled` + templates + placeholder |
| FE Banner | `app/javascript/dashboard/components/widgets/conversation/ReplyBoxBanner.vue` | Banner sempre visível quando restringido |
| i18n | `en/customRole.json`, `pt_BR/customRole.json`, `conversation.json` en/pt_BR | Labels |

## Implementation Status

- [x] Registry backend + frontend
- [x] Policy + API authorize
- [x] ReplyBox + Banner gate
- [x] i18n en/pt_BR
- [x] Specs mínimos
- [x] Checklist manual / Go-No-Go (happy path)

## Known follow-ups applied (hardening)

- [x] Templates WhatsApp/Content ocultos quando restrição assignee ativa (mantém templates na janela 24h)
- [x] `create`/`retry` re-raise `Pundit::NotAuthorizedError` (não virar 422)
- [x] Gate central no `MessageBuilder` (macros + conversation create com message)
- [x] Macros: skip `send_message` / `send_attachment` / `add_private_note` com log
- [x] `evolution_go_react` / `evolution_go_edit` exigem `reply?`

## Manual Validation Checklist

- [x] Role nova: checkbox existe e vem **desmarcado**
- [x] Sem a permissão: responde em não atribuída (comportamento atual)
- [x] Com a permissão + não atribuída: caixa desabilitada (Responder e Privada)
- [x] Banner “Assign to me” visível; após atribuir, caixa libera
- [x] Atribuída a outro agente: caixa desabilitada
- [x] Atribuída a mim: envia normalmente
- [x] API POST message sem assignee (com permissão) → 401
- [x] Agent sem custom role / Admin → sem restrição
- [x] Labels EN + pt_BR no modal
- [x] Regressão: team-unassigned / inbox_view intactos

### Hardening (revalidar)

- [ ] Com restrição + não atribuída: botões de template WhatsApp/Content **não** aparecem
- [ ] Macro com send_message em conversa não atribuída: não envia
- [ ] API unauthorized responde 401 (não 422)

## Automated validation completed

- [x] `ConversationPolicy#reply?` (com/sem permissão, assigned/unassigned/other/admin)
- [x] `CustomRole::PERMISSIONS` includes `conversation_reply_assigned_only`
- [x] FE `hasReplyAssignedOnlyRestriction`
- [x] `MessageBuilder` raises `NotAuthorizedError` when restricted + unassigned

## Deploy

Só deploy de código. **Sem rake/migration** — roles existentes permanecem sem a chave → comportamento idêntico.

## Related

- Escopo de conversas por time: [`../custom-role-team-permission-normalization/implementation-plan.md`](../custom-role-team-permission-normalization/implementation-plan.md)
- Caixa de Entrada (Inbox View): [`../custom-role-inbox-view-permission/implementation-plan.md`](../custom-role-inbox-view-permission/implementation-plan.md)
- **Agent compose:** `Custom::Conversations::AgentStartService` atribui ao iniciador no create/reopen de conversa fechada (e após promover `pending`, mesmo se auto-assign atribuir outro no `open!`), então `reply?` passa no happy path do compose. Conversa **open** de outro agente continua bloqueada no compose com **422** (mensagem clara) — distinto do **401** de `reply?` no ReplyBox.
- **Message forward:** o destino também passa por `AgentStartService` (`conversations#create`, com `conversation_id` opcional) antes de `messages#create`, para o mesmo prepare (reopen+assign / 422). Sem isso, encaminhar para conversa visível mas não atribuída 401 em `reply?`. Contactable reusa CI de grupos/LID. Ver [`../message-forward/`](../message-forward/).

## Definition of Done

- [x] Checkbox disponível, default off
- [x] UI + API alinhados
- [x] Specs mínimos
- [x] Docs feature + Related irmãos atualizados
- [x] Checklist manual aprovado (happy path)
- [ ] Hardening revalidado
