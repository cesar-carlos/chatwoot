# Automation `opened_by` — Plano de implementação (as-built)

Plano executado no MVP (ago/2026). Não editar o arquivo de plano do Cursor; esta é a documentação permanente.

---

## Fase 1 — Persistência e hooks de create

| Item | Entrega |
|------|---------|
| Stamper | `Custom::Conversations::OpenedByStamper` |
| Current | `conversation_opened_by` + reset (`# FORK:`) |
| Resolver | `prepend_mod_with` + merge no create |
| Callers | Phone sync Evolution/Go; inbound WhatsApp; controller `#create` |

## Fase 2 — Hooks de reopen

| Item | Entrega |
|------|---------|
| Incoming | `Custom::Message::OpenedByTracking` (após cycles Evolution/Wavoip) |
| Agent | `toggle_status` / status → open stamp `agent` |

## Fase 3 — Condição backend

| Item | Entrega |
|------|---------|
| YAML | `conversations.opened_by` em `filter_keys.yml` |
| Allowlist | `Custom::AutomationRule#conditions_attributes` |
| Filter service | Sem mudança (path `additional_attributes`) |

## Fase 4 — Frontend Automação

| Item | Entrega |
|------|---------|
| Constants | Condição só em created + opened |
| Options | `OPENED_BY_CONDITION_VALUES` |
| Helper / composable | Map `opened_by` |
| i18n | en + pt_BR |

## Fase 5 — Specs e deploy

| Item | Entrega |
|------|---------|
| Specs | stamper, tracking, condition, phone sync |
| Assets | `vite build` |
| Runtime | `pm2 restart chatwoot-web chatwoot-worker` |

## Fase 6 — Review pós-teste (ago/2026)

| Item | Entrega |
|------|---------|
| Current leak | `ensure` em `IncomingMessageBaseService#set_conversation` |
| Wavoip reopen | Stamp em `ConversationReopenService` |
| Wavoip/voice create | Stamp no linker outbound + `InboundCallBuilder` |
| Specs | +2 examples Wavoip reopen (17 total) |
| Docs | `current-state` / `business-rules` / backlog / README |

---

## Checklist pós-deploy (produto)

- [x] Hard refresh / testes manuais do usuário (contato / origem / Reabrir)
- [ ] Regra boas-vindas Criada: condição **Aberto por = Contato** (confirmar em todas as contas)
- [ ] Regra boas-vindas Aberta: mesma condição
- [x] Teste origem WhatsApp Web → sem menu
- [x] Teste Reabrir → sem menu
- [x] Teste contato inicia → com menu

---

## Conformidade com rules do fork

| Rule | Como |
|------|------|
| Preferir `custom/` | Stamper, Message tracking, controller, AutomationRule overlay |
| `# FORK:` mínimo | Current, filter_keys, Resolver prepend, constants FE |
| Não quebrar existente | Condição opt-in; regras sem ela inalteradas |
| Specs no mesmo PR | `spec/custom/...` espelhando overlays |
| i18n | en + pt_BR (fork) |
