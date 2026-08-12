# Automation `opened_by` — Estado atual

Inventário do código após review pós-MVP (ago/2026). Specs custom: **17 examples, 0 failures**.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Stamper | `Custom::Conversations::OpenedByStamper` — `merge_create_params`, `stamp!`, `normalize` |
| Create | `Custom::Conversations::Resolver#resolve_or_create` mergeia `opened_by` |
| Phone sync | Evolution + Evolution Go `PhoneOutgoingSyncService` → `phone` |
| WhatsApp inbound | `IncomingMessageServiceHelpers#conversation_params` → `contact` (ou `phone` se echo) |
| Current cleanup | `IncomingMessageBaseService#set_conversation` limpa `Current.conversation_opened_by` no `ensure` |
| Agent create | `Custom::Api::V1::Accounts::ConversationsController#create` → `AgentStartService` + stamp `agent` |
| Agent compose pending | `AgentStartService#prepare_active!` stamp `agent` ao promover pending → open |
| Contact reopen | `Custom::Message::OpenedByTracking` antes de `open!`/`pending!` |
| Agent reply reopen | `Custom::Message::AgentOutgoingReopen` — outgoing humano em resolved/snoozed → `open!` + stamp `agent` |
| Agent reopen | Controller `toggle_status` → stamp `agent` se vai para `open` |
| Wavoip reopen | `ConversationReopenService` → `contact` (pending/inbound) / `agent` (open/outbound) |
| Wavoip create | Outbound linker → `agent`; inbound `Voice::InboundCallBuilder` → `contact` |
| Filter YAML | `lib/filters/filter_keys.yml` → `conversations.opened_by` |
| Model allowlist | `Custom::AutomationRule#conditions_attributes` inclui `opened_by` |
| Avaliação | `ConditionsFilterService` via `additional_attributes ->> 'opened_by'` (sem mudança no service) |
| UI Automação | Condição em `conversation_created` e `conversation_opened` |
| Dropdown | `OPENED_BY_CONDITION_VALUES` + `useAutomationValues` / `automationHelper` |
| i18n | `AUTOMATION.ATTRIBUTES.OPENED_BY` + `OPENED_BY_TYPES.*` (en + pt_BR; chaves alinhadas) |
| Current | `Current.conversation_opened_by` (+ reset) |

---

## Limitações conhecidas

| Item | Motivo |
|------|--------|
| Conversas antigas sem `opened_by` | Sem backfill; filtro `equal_to contact` não casa até novo episódio |
| Eventos além de created/opened | MVP deliberadamente estreito |
| Delayed automations | `opened_by` fora de `DELAYED_CONVERSATION_ATTRIBUTES` |
| Widget / API pública create | Não seta `Current` explicitamente (fica sem stamp) |
| List filters de conversa | YAML tem a chave; FE da lista não expõe o dropdown |
| Phone em conversa resolvida + lock single | Sync cria outgoing; **não** reabre via `Message#reopen_conversation` (só incoming) — sem `conversation_opened` |
| `phone` vs `agent` na origem | Distintos de propósito; boas-vindas usam só `contact` |

---

## Review (ago/2026) — achados

### Correções aplicadas nesta passada

1. **Leak de `Current.conversation_opened_by`** no inbound WhatsApp (Sidekiq podia herdar valor no próximo job) → `ensure` em `set_conversation`.
2. **Wavoip reopen sem stamp** (`ConversationReopenService` / call upsert) → stamp `contact`/`agent` antes de `pending!`/`open!`.
3. **Wavoip outbound create** e **inbound voice create** sem `opened_by` → stamp no linker / `InboundCallBuilder`.

### Verificado OK (sem mudança)

- `ConversationBuilder` já passa por `Conversations::Resolver` → agent create via `Current` funciona.
- `toggle_status` com `status=open` só stamp quando `!open?`; resolve explícito não stamp.
- `ConditionsFilterService` + `filterQueryGenerator` (valores `{id,name}` → id) + hydration no edit.
- pt_BR automation.json alinhado com en (incl. `OPENED_BY` / delayed tabs).
- Regressão: regra sem condição `opened_by` continua casando.

---

## Mapa de arquivos

### Backend (custom / fork)

| Path | Papel |
|------|--------|
| `custom/app/services/custom/conversations/opened_by_stamper.rb` | API de stamp / merge |
| `custom/app/services/custom/conversations/resolver.rb` | Merge no create |
| `custom/app/models/custom/message/opened_by_tracking.rb` | Stamp no reopen incoming |
| `custom/app/models/custom/message.rb` | Registra prepend `OpenedByTracking` |
| `custom/app/controllers/custom/api/v1/accounts/conversations_controller.rb` | Create + toggle agent |
| `custom/app/services/custom/whatsapp/incoming_message_service_helpers.rb` | Inbound / echo |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | Limpa `Current` após resolve |
| `custom/app/services/custom/whatsapp/evolution/phone_outgoing_sync_service.rb` | Phone stamp |
| `custom/app/services/custom/whatsapp/evolution_go/phone_outgoing_sync_service.rb` | Phone stamp (Go) |
| `custom/app/services/wavoip/calls/conversation_reopen_service.rb` | Stamp no reopen voice |
| `custom/app/services/wavoip/calls/conversation_linker.rb` | Stamp outbound create |
| `custom/app/models/custom/voice/inbound_call_builder.rb` | Stamp inbound voice create |
| `custom/app/models/custom/automation_rule.rb` | Allowlist `opened_by` |

### Upstream (marcado FORK)

| Path | Papel |
|------|--------|
| `lib/current.rb` | `conversation_opened_by` |
| `lib/filters/filter_keys.yml` | Definição do filtro |
| `app/services/conversations/resolver.rb` | `prepend_mod_with('Conversations::Resolver')` |

### Frontend

| Path | Papel |
|------|--------|
| `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` | Condição nos 2 eventos |
| `app/javascript/dashboard/constants/automation.js` | `OPENED_BY_CONDITION_VALUES` |
| `app/javascript/dashboard/composables/useAutomationValues.js` | Opções dropdown |
| `app/javascript/dashboard/helper/automationHelper.js` | `conditionFilterMaps.opened_by` |
| `app/javascript/dashboard/i18n/locale/en/automation.json` | Labels EN |
| `app/javascript/dashboard/i18n/locale/pt_BR/automation.json` | Labels pt_BR |

### Specs

| Path | Papel |
|------|--------|
| `spec/custom/services/custom/conversations/opened_by_stamper_spec.rb` | Stamper |
| `spec/custom/services/custom/conversations/opened_by_tracking_spec.rb` | Create / reopen / Wavoip hooks |
| `spec/custom/services/custom/conversations/opened_by_automation_condition_spec.rb` | Filter + save + regressão |
| `spec/custom/services/custom/whatsapp/evolution/phone_outgoing_sync_service_spec.rb` | Expect `opened_by=phone` |

---

## Como depurar

| Sintoma | Onde olhar |
|---------|------------|
| Menu ainda sai no Reabrir | Regra sem condição `opened_by`; ou stamp agent falhou no `toggle_status` |
| Menu sai no WhatsApp Web | Regra sem filtro; ou create sem `phone` no Resolver |
| Menu não sai para contato | `opened_by` ausente na conversa; ConditionsFilterService; regra `equal_to` errada |
| Regra não salva | `conditions_attributes` / YAML operators |

Inspecionar no console Rails:

```ruby
Conversation.find_by(display_id: 40, account_id: 15).additional_attributes['opened_by']
```
