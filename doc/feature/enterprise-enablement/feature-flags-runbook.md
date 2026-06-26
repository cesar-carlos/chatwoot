# Feature Flags Runbook

## Limits

- `accounts.feature_flags` is a signed 64-bit bitmask managed by FlagShihTzu.
- `config/features.yml` must contain **64 or fewer** entries.
- New fork features must **repurpose deprecated slots** instead of appending to the end.
- Long-term overflow features are stored in `accounts.enabled_features_data` (jsonb) via `Accounts::FeatureStore`.

## Add a new fork feature

1. Identify a deprecated or unused slot in `config/features.yml`.
2. Replace that entry with the new feature name (do not append after position 64).
3. Add a data migration that remaps bitmasks by feature name (see `db/migrate/20260625120000_*` and `20260626120000_*`).
4. Add migration specs under `spec/migrations/`.
5. Run:
   - `bundle exec rails chatwoot:features:verify_catalog`
   - `bundle exec rails chatwoot:features:verify_accounts`

## Super Admin behavior

- Unchecked features are cleared because `selected_feature_flags=` rebuilds the enabled set.
- On self-hosted enterprise, enabling **Assignment V2** automatically enables **Advanced Assignment**.

## Post-deploy smoke test

```bash
bundle exec rails db:migrate
bundle exec rails chatwoot:features:verify_catalog
bundle exec rails chatwoot:features:verify_accounts
bundle exec rails chatwoot:features:reconcile_jsonb
```

Then update an account in `/super_admin/accounts/:id/edit` and confirm no HTTP 500.

## Jsonb cutover

1. Migrations add and backfill `enabled_features_data`.
2. `Accounts::FeatureStore` dual-writes jsonb and legacy bitmasks for catalog features.
3. Enable primary reads with installation config `FEATURE_FLAGS_JSONB_PRIMARY=true` after backfill and reconciliation.

## Deploy notes

- Use `DEPLOY_SKIP_GIT_PULL=true` only for controlled hotfix deploys.
- Standard deploys should always pull from git before build.
