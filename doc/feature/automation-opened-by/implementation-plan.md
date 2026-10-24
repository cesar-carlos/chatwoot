# Automation `opened_by` — Plano de implementação (as-built)

Plano executado. Não editar o arquivo de plano do Cursor; esta é a documentação permanente.

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
| Incoming | `Custom::Message::OpenedByTracking` |
| Agent | `toggle_status` / status → open stamp `agent` |
| Agent reply | `Custom::Message::AgentOutgoingReopen` |
| Compose | `AgentStartService` no create, no reopen e no pending → open |

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

## Fase 5 — Specs

| Item | Entrega |
|------|---------|
| Specs | stamper, tracking, condition, phone sync, agent start, agent outgoing |

## Fase 6 — Review pós-teste (ago/2026)

| Item | Entrega |
|------|---------|
| Current leak | `ensure` em `IncomingMessageBaseService#set_conversation` |
| Wavoip reopen | Stamp em `ConversationReopenService` |
| Wavoip/voice create | Stamp no linker outbound + `InboundCallBuilder` |

## Fase 7 — Revisão out/2026

| Item | Entrega |
|------|---------|
| Widget | `conversation_params` grava `opened_by=contact` |
| API pública | `Current.conversation_opened_by=contact` no create, limpo no `ensure`; payload do cliente não define o valor |
| Evolution pending | Specs: reopen para pending e segunda mensagem mantêm `contact` |
| Docs | README, regras, estado atual, backlog e esta fase |

## Fase 8 — Revisão do episódio (out/2026)

| Item | Entrega |
|------|---------|
| Pending de origem | Incoming não sobrescreve `opened_by` `phone` ou `agent` enquanto o status segue `pending` |
| Create do agente | `AgentStartService` descarta `opened_by` do payload; vale `Current` (`agent`) |

## Fase 9 — Canais, filtro, fluxo e relatório (out/2026)

| Item | Entrega |
|------|---------|
| Canais | `Current` em e-mail, Telegram, SMS, Line, Twilio, Instagram, Facebook, TikTok e Twitter. `Conversation` copia `Current` no create |
| Phone + histórico único | `reopen_as_phone!` no sync Evolution e Evolution Go |
| Automação | Condição também em `message_created` |
| Fluxo | `opened_by` nas condições; mensagem ao contato que cria conversa grava `agent` |
| Lista | Dropdown no filtro avançado e leitura local de `additional_attributes` |
| Backfill | `OpenedByBackfill` + job + `rake opened_by:backfill` |
| Relatório | Contagem `opened_by` no live report (open + pending) |

---

## Checklist pós-deploy (produto)

- [x] Hard refresh / testes manuais (contato / origem / Reabrir)
- [ ] Regra boas-vindas Criada: condição **Aberto por = Contato** em todas as contas que usam o menu
- [ ] Regra boas-vindas Aberta: mesma condição
- [x] Teste origem WhatsApp Web → sem menu
- [x] Teste Reabrir → sem menu
- [x] Teste contato inicia → com menu

---

## Conformidade com rules do fork

| Rule | Como |
|------|------|
| Preferir `custom/` | Stamper, tracking, controllers, AutomationRule |
| `# FORK:` mínimo | Current, filter_keys, Resolver, constants FE, uma linha de prepend no widget e na API pública |
| Não quebrar existente | Condição opt-in; regras sem ela inalteradas |
| Specs no mesmo change | `spec/custom/...` espelhando os overlays |
| i18n | en + pt_BR |
