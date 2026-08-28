# Inbox cache logout and membership invalidation

## Context

`GET /api/v1/accounts/:id/inboxes` already scopes via `InboxPolicy::Scope` → `user.assigned_inboxes`. The Canais sidebar and Settings inbox list read from IndexedDB `cw-store-{accountId}` (account-keyed, not user-keyed) via `CacheEnabledApiClient`. A previous user's inbox list could leak to the next login on the same browser until TTL (72h) or a cache-key bump.

Membership (`InboxMember` / `TeamMember`) did not bump the account inbox/team cache keys, so a collaborator change could leave a stale list until logout or TTL.

## Objective

1. Await IndexedDB deletion before logout redirect (logout, 401 validity check, email-change).
2. Close open `DataManager` connections first so `deleteDatabase` is not stuck behind live handles.
3. Resolve `deleteDatabase` only on `onsuccess`. `onblocked` waits (timeout ~3s) then Sentry; `onerror` Sentry then resolve so logout is not trapped.
4. Bump `inbox` / `team` cache keys on membership create/destroy.

## Implementation

| Piece | Location |
|-------|----------|
| Close DataManager connections | `app/javascript/dashboard/helper/CacheHelper/DataManager.js` (`close()`, `closeAllDataManagers`) |
| Await wipe + Sentry | `app/javascript/dashboard/store/utils/api.js` (`deleteIndexedDBOnLogout`, `clearCookiesOnLogout`) |
| Logout | `app/javascript/dashboard/api/auth.js` — only `await clearCookiesOnLogout()` |
| 401 | `app/javascript/dashboard/store/modules/auth.js` |
| Email change | `app/javascript/dashboard/routes/dashboard/settings/profile/Index.vue` |
| InboxMember cache | `app/models/inbox_member.rb` — `# FORK:` `update_cache_key('inbox')` |
| TeamMember cache | `app/models/team_member.rb` — `# FORK:` `update_cache_key('team')` |

## Manual checklist

- [ ] Administrator with many inboxes → logout → log in as restricted agent in the same browser → Canais and Settings inbox list show only assigned inboxes.
- [ ] Add/remove inbox collaborator without logout → agent's inbox list updates (cache key bump).
- [ ] 401 / email-change logout also clears IndexedDB (no leftover `cw-store-*` for that account).

## Related

- Custom role conversation scope: [`../custom-role-team-permission-normalization/implementation-plan.md`](../custom-role-team-permission-normalization/implementation-plan.md)
- Gerenciar canal (`inbox_manage`): [`../custom-role-inbox-manage-permission/implementation-plan.md`](../custom-role-inbox-manage-permission/implementation-plan.md)
