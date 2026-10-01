# Chatwoot Fork — Agent Guidelines

This file is the cross-agent entry point. Use it **together with** the detailed rules in [`.cursor/rules/`](.cursor/rules/README.mdc). The rules provide implementation details; this file records the shared workflow and points to each rule. If the two disagree, do not silently choose one: follow the safer constraint for the current task and correct the documentation.

## Rules to read

| When | Rule | Covers |
|------|------|--------|
| Every task | [Core](.cursor/rules/chatwoot-core.mdc) | Scope, errors, tests, translations, branding |
| Every task | [Architecture](.cursor/rules/architecture.mdc) | Rails/Vue layers and access-control surfaces |
| Every task | [Dev commands](.cursor/rules/chatwoot-dev-commands.mdc) | Setup, worktrees, lint and tests |
| Every task | [Fork workflow](.cursor/rules/fork-workflow.mdc) | Branches, overlays, upstream sync, hooks and markers |
| Ruby/Rails files | [Ruby conventions](.cursor/rules/ruby-conventions.mdc) | Models, controllers, migrations and specs |
| Vue/JS/TS files | [Frontend conventions](.cursor/rules/vue-frontend.mdc) | Composition API, i18n, design system and Tailwind |
| OSS, Enterprise or Custom behavior | [Enterprise overlay](.cursor/rules/enterprise-edition.mdc) | Extension points and API compatibility |
| Fork pull request | [Pull requests](.cursor/rules/pull-requests.mdc) | Product-facing PR description |

The [rules index](.cursor/rules/README.mdc) describes which files Cursor loads automatically. Agents that do not load Cursor rules automatically must read the applicable files themselves. Edit detailed rules in `.cursor/rules/` and keep this entry point accurate.

## Shared workflow

- The GitHub fork is `cesar-carlos/chatwoot`: `origin/main` contains fork work; `origin/develop` is intended to mirror `upstream/develop` after synchronization. Never commit fork work on `develop`, push to `upstream`, or open a PR against the original project.
- Create a separate worktree and branch from a freshly fetched `origin/main` for each task. Preserve unrelated changes in existing worktrees; do not assume a local `main` is current.
- Prefer config/data, then `custom/`, then existing extension points, then the smallest upstream edit marked `FORK:`. Keep OSS and Enterprise contracts compatible.
- `bin/fork-sync-upstream` prepares an isolated integration branch. It must not reset or rebase published `main`; review conflicts, tests and marker inventory before integrating into the fork.
- Production deployment, migrations, restarts, and publication are separate actions. Do them only when the user authorizes that scope.

## Implementation and verification

- Prefer the smallest production-ready change. Validate API inputs at the request boundary; do not swallow failures or add speculative retries and guards. Check authorization policy, list scope, counts and frontend gates together when access changes.
- Use Composition API with `<script setup>` for Vue, shared composables/design-system utilities, i18n in templates, and Tailwind utilities. For Ruby, use strong params, project exceptions and the existing overlay mechanisms.
- Tests should match the risk of the change. New `custom/app` behavior requires a matching `spec/custom` test; bug fixes and contract changes need focused regression coverage. Do not add redundant tests for documentation-only changes.
- Before any Ruby/Bundler command run `eval "$(rbenv init -)"`; prefer `bundle exec`. Run targeted tests/lint, `git diff --check`, and `bin/fork-inventory` when `FORK:` markers change.
- English is required for source strings. Fork-specific user-facing strings may also update `pt_BR`; do not manually edit other community locales. Crowdin syncs are a separate exception. Preserve brand and machine-readable terms and keep the Crowdin glossary current.
- Keep commits small and conventional (`type(scope): subject`). Update feature documentation when requested or when a changed operational contract would otherwise leave it inaccurate.

See [Dev commands](.cursor/rules/chatwoot-dev-commands.mdc) for setup, seeding and test commands, and [Fork workflow](.cursor/rules/fork-workflow.mdc) before any branch synchronization or push.
