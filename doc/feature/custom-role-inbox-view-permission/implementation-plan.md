# Custom Role — Inbox View Permission (Caixa de Entrada)

## Context

A tela **Caixa de Entrada** (`/accounts/:id/inbox-view`) é o Inbox View: feed de notificações / mensagens recentes. Não é a membership de canais (WhatsApp, e-mail, etc.).

Hoje a rota usa `[...ROLES, ...CONVERSATION_PERMISSIONS]`, então qualquer custom role com permissão de conversa vê o menu automaticamente. Não existe checkbox dedicado para ligar/desligar essa tela.

## Objective

Introduzir a permissão `inbox_view_manage` ponta a ponta:

1. Checkbox no cadastro de custom role
2. Gate de rota/sidebar
3. Gate na API de notifications
4. Migração compatível (grant automático para roles com `conversation_*`)
5. Documentação e aceite manual

## Decisões fechadas

- **Permissão:** `inbox_view_manage`
- **Sem custom role:** `administrator` e `agent` continuam vendo (via `ROLES`)
- **Com custom role:** só vê se `inbox_view_manage` estiver marcado
- **Compatibilidade:** one-shot grant de `inbox_view_manage` para todo `CustomRole` que já tenha qualquer `conversation_*`
- **Independente** de `conversation_manage` (sem auto-fill no modal)
- **Feature flag** `inbox_view` permanece desacoplada

## Access Semantics

| Perfil | Vê Caixa de Entrada? |
|--------|----------------------|
| Administrator | Sim |
| Agent sem custom role | Sim |
| Custom role **com** `inbox_view_manage` | Sim |
| Custom role **sem** `inbox_view_manage` | Não (menu, rota, API) |
| Custom role só contact/report/KB | Não (já era assim) |

## Architecture (Fork)

| Camada | Arquivo | Papel |
|--------|---------|-------|
| Permissão | `enterprise/app/models/custom_role.rb` | `PERMISSIONS` + `# FORK:` |
| Policy OSS | `app/policies/notification_policy.rb` | `access?` true + `prepend_mod_with` |
| Policy fork | `custom/app/policies/custom/notification_policy.rb` | Gate custom role |
| Controller | `app/controllers/api/v1/accounts/notifications_controller.rb` | `before_action` authorize (`# FORK:`) |
| Migração | `custom/app/services/custom/custom_roles/grant_inbox_view_permission_service.rb` + rake | Grant idempotente |
| FE constants | `app/javascript/dashboard/constants/permissions.js` | Registry + `INBOX_VIEW_PERMISSIONS` |
| FE routes | `app/javascript/dashboard/routes/dashboard/inbox/routes.js` | meta.permissions |
| FE sidebar | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | unread fetch condicional |
| i18n | `en/customRole.json`, `pt_BR/customRole.json` | Labels |

## Implementation Status

- [x] Registry backend + frontend
- [x] Policy + API authorize
- [x] Route/sidebar gate
- [x] i18n en/pt_BR
- [x] Grant service + rake task
- [x] Specs mínimos
- [ ] Checklist manual / Go-No-Go

## Known follow-ups applied (hardening)

- [x] Rota legada `notifications_index` alinhada a `INBOX_VIEW_ROUTE_PERMISSIONS`
- [x] Command palette aponta para `inbox-view` e exige `hasInboxViewPermission`
- [x] Sidebar: `watch(accountId, canAccessInboxView)` com refetch/clear (não só `onMounted`)
- [x] ActionCable ignora `notification.*` sem permissão de Inbox View
- [x] `CLEAR_NOTIFICATIONS` zera `unreadCount`/`count` para evitar badge stale

## Manual Validation Checklist

### Setup

- [ ] Rodar `bundle exec rake custom_roles:grant_inbox_view_permission`
- [ ] Role com conversation_* (após migrate) ainda vê Caixa de Entrada
- [ ] Role com conversation_* sem `inbox_view_manage` (desmarcar) → menu some

### Expected

- [ ] Deep link `/inbox-view` sem permissão → redirect
- [ ] API notifications sem permissão → 403
- [ ] Remarcar permissão → menu e feed voltam
- [ ] Agent sem custom role → continua vendo
- [ ] Admin → continua vendo
- [ ] Unread count não polui quando sem permissão
- [ ] Labels EN + pt_BR no modal/lista
- [ ] Regressão: team-unassigned / conversation filters intactos

## Automated validation completed

- [x] `NotificationPolicy` (custom role with/without `inbox_view_manage`)
- [x] `GrantInboxViewPermissionService` (grant / skip / idempotent)
- [x] Notifications request specs (200 / 401)
- [x] `CustomRole::PERMISSIONS` includes `inbox_view_manage`
- [x] FE `permissionsHelper` + `routeHelpers` (inbox_view gate)

## Deploy

```bash
# Após deploy do código (PERMISSIONS já inclui inbox_view_manage):
bundle exec rake custom_roles:grant_inbox_view_permission
```

Idempotente — seguro reexecutar.

## Related

- Feature irmã (escopo de conversas por time): [`../custom-role-team-permission-normalization/implementation-plan.md`](../custom-role-team-permission-normalization/implementation-plan.md)
- Reply only when assigned: [`../custom-role-reply-assigned-only/implementation-plan.md`](../custom-role-reply-assigned-only/implementation-plan.md)

## Definition of Done

- [x] Checkbox disponível no custom role
- [x] Rota/sidebar/API alinhados
- [x] Migração compatível documentada e implementada
- [x] Specs mínimos
- [ ] Checklist manual aprovado
