# Chatwoot Development Guidelines

**Source of truth:** `.cursor/rules/` — edit rules there; this file is a Windsurf index.

## Quick start

```bash
bundle install && pnpm install
eval "$(rbenv init -)"
pnpm dev
```

## Rules

| Always applied | File-scoped | On demand |
|----------------|-------------|-----------|
| `chatwoot-core.mdc` | `ruby-conventions.mdc` | `pull-requests.mdc` |
| `chatwoot-dev-commands.mdc` | `vue-frontend.mdc` | `README.mdc` |
| `architecture.mdc` | `enterprise-edition.mdc` | |
| `fork-workflow.mdc` | | |

Fork: `bin/fork-sync-upstream` · details in `.cursor/rules/fork-workflow.mdc`
