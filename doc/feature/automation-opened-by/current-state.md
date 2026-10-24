# Automation `opened_by` — Estado atual

Inventário do código após a revisão de out/2026.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Stamper | `Custom::Conversations::OpenedByStamper` — `merge_create_params`, `stamp!`, `normalize` |
| Create | `Custom::Conversations::Resolver#resolve_or_create` aplica o merge só na criação |
| Phone sync | Evolution + Evolution Go `PhoneOutgoingSyncService` → `phone` na criação |
| WhatsApp inbound | `IncomingMessageServiceHelpers#conversation_params` → `contact`, ou `phone` se echo |
| Current cleanup | `IncomingMessageBaseService#set_conversation` zera `Current.conversation_opened_by` no `ensure` |
| Agent create | `ConversationsController#create` → `AgentStartService` + stamp `agent`. `opened_by` enviado pelo cliente é descartado |
| Agent compose | `AgentStartService` stamp `agent` ao reabrir resolved/snoozed e ao promover pending → open |
| Contact reopen | `Custom::Message::OpenedByTracking` antes de `open!` / `pending!`. Não sobrescreve `phone` nem `agent` se a conversa já está `pending` |
| Agent reply reopen | `Custom::Message::AgentOutgoingReopen` — outgoing humano em resolved/snoozed → `open!` + stamp `agent` |
| Agent reopen | `toggle_status` → stamp `agent` só quando o destino é `open` e a conversa ainda não está aberta |
| Wavoip reopen | `ConversationReopenService` → `contact` (pending/inbound) / `agent` (open/outbound) |
| Wavoip / voice create | Linker outbound → `agent`; `Voice::InboundCallBuilder` → `contact` |
| Widget create | `Custom::Api::V1::Widget::BaseController#conversation_params` → `contact` |
| API pública create | `Custom::Public::Api::V1::Inboxes::ConversationsController#create_conversation` seta `Current` → `contact` e limpa no `ensure` |
| Evolution pending | Reopen resolved/snoozed grava `contact` e `evolution_pending_since`; a segunda incoming abre e mantém `contact` |
| Filter YAML | `lib/filters/filter_keys.yml` → `conversations.opened_by` |
| Model allowlist | `Custom::AutomationRule#conditions_attributes` inclui `opened_by` |
| Avaliação | `ConditionsFilterService` via `additional_attributes ->> 'opened_by'` |
| UI Automação | Condição em `conversation_created`, `conversation_opened` e `message_created` |
| Filtro da lista | Dropdown **Aberto por** no filtro avançado; a lista local lê `additional_attributes.opened_by` |
| Workflow | `ConversationWorkflowRule#conditions_attributes` inclui `opened_by` |
| Relatório ao vivo | `GET /api/v2/.../live_reports/conversation_metrics` inclui `opened_by` (open + pending) |
| Backfill | `lib/tasks/opened_by.rake` e `Custom::Conversations::OpenedByBackfillJob` |
| Dropdown | `OPENED_BY_CONDITION_VALUES` + `useAutomationValues` / `automationHelper` |
| i18n | `AUTOMATION.ATTRIBUTES.OPENED_BY` + `OPENED_BY_TYPES.*` (en + pt_BR) |
| Current | `Current.conversation_opened_by` (+ reset) |

O valor explícito em `additional_attributes` ganha de `Current`. Valor fora de `contact|agent|phone` é ignorado. No create do agente, `opened_by` do payload é removido antes do merge, então vale `agent`.

---

## Limitações conhecidas

| Item | Motivo |
|------|--------|
| Conversas antigas sem `opened_by` | `rake opened_by:backfill` (ou `OpenedByBackfillJob`) infere pela primeira mensagem. Não roda sozinho. Até lá, `equal_to contact` não casa |
| Delayed automations | `opened_by` fora de `DELAYED_CONVERSATION_ATTRIBUTES` (`status` + `inbox_id`) |
| Phone sem histórico único | Conversa já resolved não é reaberta; o sync cria outra com `phone` |
| Eco do chat sem `source_id` (Evolution Node) | Pode criar uma segunda bolha com ícone de celular. Evolution Go adota o eco na mensagem do agente. `opened_by` não muda se a conversa do agente já existe |
| `phone` vs `agent` | Distintos de propósito; boas-vindas usam só `contact` |
| Ciclo `conversation_pending` | A primeira mensagem deixa `pending`. **Conversa Aberta** dispara na mensagem seguinte, quando o status vira `open` |

---

## Mapa de arquivos

### Backend (custom / fork)

| Path | Papel |
|------|--------|
| `custom/app/services/custom/conversations/opened_by_stamper.rb` | API de stamp / merge / `with_current` / `reopen_as_phone!` |
| `custom/app/services/custom/conversations/incoming_opened_by.rb` | Envolve o `perform` dos canais inbound |
| `custom/app/services/custom/conversations/opened_by_backfill.rb` | Inferência one-shot |
| `custom/app/services/custom/conversations/opened_by_summary.rb` | Contagem do relatório ao vivo |
| `custom/app/services/custom/conversations/resolver.rb` | Merge no create; Wavoip reusa a conversa mais recente |
| `custom/app/services/custom/conversations/agent_start_service.rb` | Create e reopen do compose do agente |
| `custom/app/models/custom/message/opened_by_tracking.rb` | Stamp `contact` no reopen incoming |
| `custom/app/models/custom/message/agent_outgoing_reopen.rb` | Stamp `agent` na resposta outgoing em resolved/snoozed |
| `custom/app/models/custom/message.rb` | Ordem dos prepends (`AgentOutgoingReopen` por último, então roda primeiro) |
| `custom/app/models/custom/message/evolution_conversation_cycle.rb` | Pending cycle; regrava `additional_attributes` sem apagar `opened_by` |
| `custom/app/controllers/custom/api/v1/accounts/conversations_controller.rb` | Create + toggle do agente |
| `custom/app/controllers/custom/api/v1/widget/base_controller.rb` | Create do widget → `contact` |
| `custom/app/controllers/custom/public/api/v1/inboxes/conversations_controller.rb` | Create da API pública → `contact` |
| `custom/app/services/custom/whatsapp/incoming_message_service_helpers.rb` | Inbound / echo |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | Limpa `Current` após resolve |
| `custom/app/services/custom/whatsapp/evolution/phone_outgoing_sync_service.rb` | Phone stamp |
| `custom/app/services/custom/whatsapp/evolution_go/phone_outgoing_sync_service.rb` | Phone stamp (Go) |
| `custom/app/services/wavoip/calls/conversation_reopen_service.rb` | Stamp no reopen de voz |
| `custom/app/services/wavoip/calls/conversation_linker.rb` | Stamp no create outbound |
| `custom/app/models/custom/voice/inbound_call_builder.rb` | Stamp no create inbound de voz |
| `custom/app/models/custom/automation_rule.rb` | Allowlist `opened_by` |

### Upstream (marcado FORK)

| Path | Papel |
|------|--------|
| `lib/current.rb` | `conversation_opened_by` |
| `lib/filters/filter_keys.yml` | Definição do filtro |
| `app/services/conversations/resolver.rb` | `prepend_mod_with('Conversations::Resolver')` |
| `app/controllers/api/v1/widget/base_controller.rb` | `prepend_mod_with` do widget |
| `app/controllers/public/api/v1/inboxes/conversations_controller.rb` | `prepend_mod_with` da API pública |

### Frontend

| Path | Papel |
|------|--------|
| `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` | Condição nos 2 eventos |
| `app/javascript/dashboard/constants/automation.js` | `OPENED_BY_CONDITION_VALUES` |
| `app/javascript/dashboard/composables/useAutomationValues.js` | Opções do dropdown |
| `app/javascript/dashboard/helper/automationHelper.js` | `conditionFilterMaps.opened_by` |
| `app/javascript/dashboard/helper/filterQueryGenerator.js` | `{id,name}` ou string → id na gravação |
| `app/javascript/dashboard/i18n/locale/en/automation.json` | Labels EN |
| `app/javascript/dashboard/i18n/locale/pt_BR/automation.json` | Labels pt_BR |

### Specs

| Path | Papel |
|------|--------|
| `spec/custom/services/custom/conversations/opened_by_stamper_spec.rb` | Stamper |
| `spec/custom/services/custom/conversations/opened_by_tracking_spec.rb` | Create, reopen, Wavoip, ciclo Evolution |
| `spec/custom/services/custom/conversations/opened_by_automation_condition_spec.rb` | Filtro, save e regra sem a condição |
| `spec/custom/services/custom/conversations/agent_start_service_spec.rb` | Compose do agente |
| `spec/custom/models/custom/message/agent_outgoing_reopen_spec.rb` | Resposta outgoing |
| `spec/custom/services/custom/whatsapp/evolution/phone_outgoing_sync_service_spec.rb` | `opened_by=phone` |
| `spec/custom/controllers/opened_by_contact_create_spec.rb` | Widget e API pública |

---

## Como depurar

| Sintoma | Onde olhar |
|---------|------------|
| Menu ainda sai no Reabrir | Regra sem condição `opened_by`; stamp do `toggle_status` ou do `AgentOutgoingReopen` |
| Menu sai no WhatsApp Web | Regra sem filtro; create do phone sync sem `phone` |
| Menu não sai para contato | `opened_by` ausente (canal sem hook, conversa legada, ou ciclo ainda `pending` numa regra de **Conversa Aberta**) |
| Regra não salva | `conditions_attributes` ou operadores do YAML |
| Valor some no ciclo pending | `evolution_conversation_cycle.rb` regravou `additional_attributes` sem a chave |
