# Automation message variables — Plano de implementação (as-built)

## MVP

| Fase | Entrega |
|------|---------|
| Backend | Liquidable + rule drop + phone alias |
| FE | Chips + prévia sob editor |
| Docs / specs | Pasta feature + specs custom |

## Polish (melhorias)

| Fase | Entrega |
|------|---------|
| UX | Cursor insert, MESSAGE_VARIABLES account/rule, agent hint |
| Email + macros | MessageContentRenderer, send_email_to_team, MacroDrop |
| Workflow | SendMessageToContactService → Liquid |
| Prévia / filtros | Vuex samples + filter snippet chips |
| Specs / docs | 13 examples; current-state / backlog atualizados |

---

## Checklist produto

- [ ] Hard refresh
- [ ] Automação: chip insere na posição do cursor
- [ ] Menu `{{` lista account.name e rule.name
- [ ] Email ao time: `{{contact.name}}` no corpo
- [ ] Macro: `{{macro.name}}` na mensagem
- [ ] Workflow: mensagem ao contato com Liquid do trigger

---

## Conformidade fork

| Rule | Como |
|------|------|
| Preferir `custom/` | Renderer, drops, overlays ActionService/Macros/Workflow |
| `# FORK:` mínimo | Editor defineExpose; ContactDrop phone |
| i18n | en + pt_BR |
| Specs | `spec/custom/...` |
