# Custom Role — Inbox Manage Permission (Gerenciar Canal)

## Context

Settings → Caixas de Entrada was administrator-only. Custom-role agents who already manage a channel as inbox collaborators still could not open inbox settings (agents, templates, secrets, Wavoip, etc.). Create/delete channel must stay administrator-only.

This is Layer 2 on top of `InboxMember` (Layer 1): `inbox_manage` grants admin-parity **update** on **assigned** inboxes only.

## Objective

Introduce `inbox_manage` end to end:

1. Checkbox on custom role
2. Settings inbox list + show routes (wizard / new / delete stay admin)
3. Policy: update + `manage_members?`; not `create?` / `destroy?`
4. Inbox members API uses `manage_members?` so collaborator edits cannot unlock channel create/delete

## Access semantics

| Profile | Settings → Caixas de Entrada |
| --- | --- |
| Administrator | All inboxes; create and delete |
| Agent, no custom role | Hidden (unchanged) |
| Custom role + `inbox_manage` | Only assigned inboxes; edit tabs including agents/secrets; no create/delete |
| Custom role without `inbox_manage` | Hidden |

## Architecture (Fork)

| Layer | File | Role |
| --- | --- | --- |
| Permission list | `enterprise/app/models/custom_role.rb` | `inbox_manage` in `PERMISSIONS` (`# FORK:`) |
| OSS policy | `app/policies/inbox_policy.rb` | `manage_members?` default administrator; `prepend_mod_with` |
| Custom policy | `custom/app/policies/custom/inbox_policy.rb` | update/avatar/bot/templates/health/secrets/calling/Wavoip + `manage_members?` if permission **and** assigned inbox. Class-level `Inbox` `update?` is **denied** (fail-closed). |
| Members API | `app/controllers/api/v1/accounts/inbox_members_controller.rb` | authorize `:manage_members?` |
| Inboxes API | `app/controllers/api/v1/accounts/inboxes_controller.rb` | `# FORK:` `check_authorization` uses `authorize(@inbox)` when the instance is loaded (index/create stay class-level) |
| FE constants | `dashboard/constants/permissions.js` | `inbox_manage` + `INBOX_MANAGE_ROUTE_PERMISSIONS` |
| Routes | `inbox.routes.js` | list + show: `administrator` or `inbox_manage`; wizard stays `administrator` |
| List UI | `inbox/Index.vue` | gear if admin or `inbox_manage`; New + trash `isAdmin` |
| Show UI | `inbox/Settings.vue` | after `inboxes/get`, bounce to list if the inbox is missing (fail-closed) |
| i18n | `en` + `pt_BR` `customRole.json` | `INBOX_MANAGE` |

`inbox_manage` is **admin-parity `update?`** on assigned inboxes: Evolution, Wavoip, `move_history`, secrets, calling, templates, and collaborators are included. Create/delete stay administrator-only.

## Note E — Audit

Enterprise `Audit::Inbox` and `Audit::InboxMember` already log changes whoever made them. `inbox_manage` does not need a new audit surface.

## Manual checklist

- [ ] Custom role with `inbox_manage` + inbox membership: Settings list shows only assigned inboxes; gear opens settings.
- [ ] New inbox and delete channel stay hidden / API 401.
- [ ] Collaborator tab (agents) works; POST/PUT/DELETE inbox members 200.
- [ ] Same role without membership: cannot update that inbox (403).
- [ ] Agent without `inbox_manage`: Settings → Caixas de Entrada hidden.

## Related

- Escopo de conversas por time: [`../custom-role-team-permission-normalization/implementation-plan.md`](../custom-role-team-permission-normalization/implementation-plan.md)
- Caixa de Entrada (Inbox View): [`../custom-role-inbox-view-permission/implementation-plan.md`](../custom-role-inbox-view-permission/implementation-plan.md)
- Reply only when assigned: [`../custom-role-reply-assigned-only/implementation-plan.md`](../custom-role-reply-assigned-only/implementation-plan.md)
- Inbox IndexedDB / membership cache: [`../inbox-cache-logout-invalidation/implementation-plan.md`](../inbox-cache-logout-invalidation/implementation-plan.md)
