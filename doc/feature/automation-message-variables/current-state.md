# Automation message variables — Estado atual

Inventário após pacote de melhorias (ago/2026). Specs relacionados: **13 examples, 0 failures**.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Liquid base | `Liquidable` + `Custom::Liquid::MessageContentRenderer` |
| Chips + prévia | `AutomationMessageVariables.vue` (Automação textarea + email ao time) |
| Insert no cursor | `Editor.insertContentIntoEditor` exposto; chips usam ref |
| Menu `{{` | `MESSAGE_VARIABLES` inclui `account.name` e `rule.name` |
| Hint assignee | `AUTOMATION.ACTION.VARIABLES.AGENT_HINT` |
| Filtros Liquid (chips) | `AUTOMATION_LIQUID_FILTER_SNIPPETS` |
| Prévia enriquecida | Account/inbox/contact do Vuex quando disponíveis |
| `rule.name` | AutomationRule + ConversationWorkflowRule |
| `macro.name` | MacroDrop + `Current.executed_by` no macro perform |
| `contact.phone` | Alias FORK em ContactDrop |
| Email ao time | Liquid antes do mailer |
| Workflow send-to-contact | Liquid no trigger conversation (não no destino) |

---

## Limitações conhecidas

| Item | Motivo |
|------|--------|
| `conversation.id` = display_id | Semântica ConversationDrop |
| `agent.*` sem assignee | Sender nil na automação |
| HSM WhatsApp | Fora de escopo |
| Filtros na prévia | Expressões com `\| default` não são resolvidas na prévia (só chaves simples) |

---

## Mapa de arquivos (destaque)

| Path | Papel |
|------|--------|
| `custom/app/services/custom/liquid/message_content_renderer.rb` | Renderer compartilhado |
| `custom/app/drops/automation_rule_drop.rb` / `macro_drop.rb` | Drops |
| `custom/app/models/custom/message/liquid_rule_context.rb` | Message Liquid rule/macro |
| `custom/app/services/custom/automation_rules/action_service.rb` | Email team Liquid |
| `custom/app/services/custom/macros/execution_service.rb` | executed_by = macro |
| `custom/.../send_message_to_contact_service.rb` | Workflow via Liquid |
| `.../AutomationMessageVariables.vue` | Chips / prévia / filtros |
| `.../WootWriter/Editor.vue` | `defineExpose` insert |
| `shared/constants/messages.js` | Menu `{{` keys |

---

## Review melhorias

Correções / entregas deste pacote: cursor ProseMirror, menu account/rule, hint agent, email team, macros, workflow Liquid, prévia Vuex, filter chips.
