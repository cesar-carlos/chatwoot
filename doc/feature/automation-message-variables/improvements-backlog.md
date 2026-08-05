# Automation message variables — Backlog de melhorias

## Feito (MVP + polish)

- [x] Chips + prévia nas ações textarea da Automação
- [x] Reuso do Liquid existente
- [x] Alias `contact.phone`
- [x] `{{rule.name}}` via Current.executed_by / renderer
- [x] Correção MESSAGE_VARIABLES → phone_number
- [x] i18n en + pt_BR
- [x] Specs custom
- [x] Docs em `doc/feature/automation-message-variables/`
- [x] Insert no cursor do ProseMirror
- [x] `account.name` / `rule.name` no menu `{{`
- [x] Hint de assignee (`agent.*`)
- [x] Liquid em `send_email_to_team`
- [x] Chips no input de email ao time
- [x] `macro.name` + executed_by em macros
- [x] Workflow send-to-contact unificado em Liquid
- [x] Prévia com dados Vuex
- [x] Chips atalho de filtros Liquid

---

## P2 — Depois

| Item | Notas |
|------|-------|
| Prévia de expressões com filtros | Hoje a prévia só resolve chaves simples |
| Unificar labels i18n dos chips | Snippets de filtro ainda em Liquid EN |

---

## Fora de escopo

- HSM / templates oficiais WhatsApp
- Mudar `conversation.id` Liquid para id interno do banco
- Backfill de textos antigos nas regras
