# Automation `opened_by` — Backlog de melhorias

## Feito (MVP + review)

- [x] Persistência `opened_by` em `additional_attributes`
- [x] Stamp create (contact / agent / phone)
- [x] Stamp reopen (contact / agent)
- [x] Condição Automação em created + opened
- [x] i18n en + pt_BR
- [x] Specs custom
- [x] Docs em `doc/feature/automation-opened-by/`
- [x] Review pós-teste: limpar `Current` no inbound WhatsApp
- [x] Review: stamp Wavoip reopen + create (inbound/outbound voice)

---

## P1 — Próximo

| Item | Notas |
|------|-------|
| Widget / API públicas de create | Setar `opened_by=contact` (ou agent) explicitamente nos controllers widget |
| Smoke checklist documentado no runbook de conta | Conta 15 — regras boas-vindas com filtro |

---

## P2 — Depois

| Item | Notas |
|------|-------|
| Phone reopen em resolved + lock single | Se produto quiser `conversation_opened` quando origem manda em conversa resolvida |
| Expor condição em `message_created` | Se produto quiser “primeira msg do contato” além de open/create |
| Filtro na lista de conversas | Reusar YAML; FE de advanced filters |
| Backfill opcional | Job one-shot: inferir pela 1ª mensagem (incoming→contact, phone_sent→phone) |
| Relatórios | Contagem de conversas por `opened_by` |
| Workflow rules | Reutilizar atributo em condições de regras de conversa se fizer sentido |

---

## Fora de escopo (ainda)

- Unificar `agent` + `phone` num único valor `origin` (quebraria configs já feitas)
- Alterar regras existentes no banco automaticamente
- Delayed automations com `opened_by`
