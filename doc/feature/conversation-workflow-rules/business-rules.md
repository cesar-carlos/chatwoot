# Conversation Workflow Rules — Regras de negócio

Documento normativo para implementação. Prevalece sobre código até revisão explícita.

---

## 1. Tipos de gatilho (`trigger_type`)

### 1.1 `conversation_inactivity`

**Definição:** nenhuma atividade na conversa por X minutos.

**Query:** `status = open AND last_activity_at < now - duration_minutes`

**Opção `ignore_waiting`:** se `true`, adicionar `waiting_since IS NULL`.

**Ação típica:** mensagem template + ações + `resolve_on_match: true`.

**Feature flag:** `auto_resolve_conversations`

### 1.2 `agent_no_reply`

**Definição:** cliente aguardando resposta humana há X minutos.

**Query:**

```sql
status = open  -- Fase 2.1: OR pending pós-handoff
AND waiting_since IS NOT NULL
AND waiting_since < now - duration_minutes
```

**Feature flag:** `conversation_agent_no_reply_rules`

**Ação típica:** escalar — **não** resolver por default.

### 1.3 `first_response_overdue`

**Definição:** conversa **nunca atendida** (`first_reply_created_at IS NULL`) há X minutos desde `waiting_since`.

**Feature flag:** `conversation_agent_no_reply_rules`

**Ação típica:** atribuir equipe, label “não atendida”.

### 1.4 `unassigned_too_long`

**Definição:** conversa aberta **sem assignee** há X minutos desde `created_at`.

**Feature flag:** `conversation_agent_no_reply_rules`

### 1.5 `pending_stale`

**Definição:** conversa em **pending** sem atividade (`last_activity_at`) há X minutos.

**Feature flag:** `conversation_agent_no_reply_rules`

### 1.6 `customer_no_reply`

**Definição:** última mensagem é **outgoing** (agente/bot) e o cliente não respondeu há X minutos.

**Feature flag:** `auto_resolve_conversations`

**Job per-message:** agenda ao enviar mensagem outgoing (`ScheduleOnMessageScheduler#perform_for_outgoing_message`).

### 1.7 Semântica de `waiting_since` (importante)

| Fato | Implicação |
|------|------------|
| `before_create :ensure_waiting_since` seta `waiting_since = created_at` | Relógio começa na **criação** da conversa |
| Incoming só seta se `waiting_since` blank | Segundo incoming **não reinicia** o timer |
| Bot/humano responde | Zera `waiting_since` (salvo `preserve_waiting_since`) |
| Nota privada / automação | **Não** zera |

**Filtros opcionais por regra (Fase 2.1):**

- `require_no_first_reply: true` → `first_reply_created_at IS NULL` (“nunca atendida”)
- `statuses: ['open', 'pending']` → incluir pending pós-handoff bot

### 1.8 Matriz comparativa

| Cenário | Inatividade | Agente não respondeu |
|---------|-------------|----------------------|
| Cliente mandou msg, agente calado | Pode | **Sim** |
| Agente fez nota privada | `last_activity_at` ↑ | **Sim** (waiting continua) |
| Bot respondeu | Depende | **Não** |
| Workflow `send_message` default | — | **Não** zera waiting |
| Workflow `send_message` + `counts_as_agent_reply` | — | **Zera** waiting |

---

## 2. Filtros e condições

### 2.1 Campos da regra (sempre)

| Campo | Tipo | Default |
|-------|------|---------|
| `inbox_ids` | `integer[]` | `null` = todas |
| `duration_minutes` | integer | 10 .. 1_439_856 |
| `ignore_waiting` | boolean | `false` (só inatividade) |
| `resolve_on_match` | boolean | `false`; `true` para legacy inatividade |
| `active`, `position` | | ordem de avaliação |

### 2.2 Condições JSON (Fase 2)

Formato idêntico a `AutomationRule#conditions`. Avaliar com `AutomationRules::ConditionsFilterService`.

**Whitelist Fase 2:** `assignee_id`, `team_id`, `labels`, `priority`

**Operadores:**
- `assignee_id`, `team_id`, `labels` — `equal_to`, `not_equal_to`, `is_present`, `is_not_present`
- `priority` — `equal_to`, `not_equal_to`

**Fase 3+:** custom attributes de conversa

Duração **não** é condição AND — pertence ao gatilho.

### 2.3 Multi-regra

**Todas** as regras ativas que match executam, na ordem de `position`, salvo dedup.

**Escalonamento em níveis:** criar N regras (ex.: 15 min label, 120 min assign, 1440 min resolve) — cada uma com dedup independente.

---

## 3. Ações

### 3.1 Executor

Usar **`Custom::ConversationWorkflow::ActionService`** (não `AutomationRules::ActionService` direto):

- `Current.executed_by = workflow_rule`
- Mensagens: `content_attributes: { conversation_workflow_rule_id: id }`
- Espelha padrão de `AutomationRules::ActionService`

### 3.2 Formato

```json
{
  "action_name": "send_message",
  "action_params": ["Estamos verificando..."],
  "counts_as_agent_reply": false
}
```

`counts_as_agent_reply` (opt-in, só `send_message`): se `true`, limpar `waiting_since` após envio.

#### `send_message_to_contact`

Abre (ou reusa) uma conversa com **outro contato** em uma inbox escolhida e envia mensagem com dados da conversa que disparou a regra:

```json
{
  "action_name": "send_message_to_contact",
  "action_params": [
    5,
    42,
    "Conversa {{conversation.display_id}} do {{contact.name}} precisa de atenção."
  ],
  "counts_as_agent_reply": false
}
```

| Posição | Campo | Tipo |
|---------|-------|------|
| `[0]` | `inbox_id` | integer — inbox pela qual enviar |
| `[1]` | `contact_id` | integer — contato destinatário |
| `[2]` | message template | string — com `{{variáveis}}` |

Variáveis interpoladas a partir da conversa **que bateu na regra** (não do destinatário):

| Variável | Valor |
|----------|-------|
| `{{conversation.id}}` | ID interno |
| `{{conversation.display_id}}` | Número de exibição |
| `{{contact.name}}` / `{{contact.email}}` / `{{contact.phone}}` | Contato da conversa origem |
| `{{inbox.name}}` | Inbox da conversa origem |
| `{{rule.name}}` | Nome da regra |

**Runtime:** `ContactInboxBuilder` → `ConversationBuilder` / `Conversations::Resolver` → `Messages::MessageBuilder` com `content_attributes.conversation_workflow_rule_id`.

| Aspecto | Comportamento |
|---------|---------------|
| Conversa destino | Resolver **reusa** a conversa aberta mais recente do `contact_inbox` (ou qualquer se `lock_to_single_conversation`); só cria se não houver |
| Canais UI | WhatsApp, Wavoip, Twilio, SMS, Email, API, WebWidget (alinhado ao `ContactInboxBuilder`) |
| Identificador | WhatsApp/SMS/Twilio exigem telefone; Email exige e-mail; API/WebWidget geram UUID |
| WhatsApp 24h | Texto livre via `MessageBuilder` — **sem HSM**; fora da janela de sessão o provedor pode rejeitar |
| Validação FE | Exige `inbox_id`, `contact_id` e mensagem não vazia |
| Falha | Inbox/contato inválidos, mensagem em branco, canal sem identificador → **warning + skip** (não aborta as demais ações); sem feedback na UI admin |

> **i18n:** placeholders de exemplo com `{{…}}` literais devem usar escape vue-i18n `{'{{'}…{'}}'}` — `{{` cru no JSON quebra o message-compiler (`Not allowed nest placeholder`).

### 3.3 Whitelist

| Ação | Inatividade | Todos os outros |
|------|:-----------:|:---------------:|
| `add_label` / `remove_label` | ✓ | ✓ |
| `add_private_note` | ✓ | ✓ |
| `send_message` | ✓ | ✓ |
| `send_message_to_contact` | ✓ | ✓ |
| `assign_agent` / `assign_team` | ✓ | ✓ |
| `remove_assigned_agent` / `remove_assigned_team` | ✓ | ✓ |
| `send_webhook_event` | ✓ | ✓ |
| `send_email_to_team` / `send_email_transcript` | ✓ | ✓ |
| `change_priority` | ✓ | ✓ |
| `send_attachment` | ✗ (log warning) | ✗ (log warning) |
| `resolve_conversation` | ✗ (usar `resolve_on_match`) | ✓ |
| `snooze` / `open` / `pending` | ✗ | ✗ |

> **Nota:** `conversation_inactivity` resolve via flag `resolve_on_match: true` no modelo, não via ação — mantém a distinção semântica entre "template + resolve" do legacy e ações avulsas. O model exclui `resolve_conversation` da whitelist para inatividade (`actions_attributes`).

> **`send_attachment`:** bloqueado na UI via `DISALLOWED_ACTIONS`; no backend, loga `warning` e retorna sem enviar.

> **`send_message_to_contact`:** ação exclusiva do workflow (`WORKFLOW_ONLY_ACTIONS`); não existe na Automação. UI: `WorkflowContactMessageInput.vue`.

### 3.4 Ordem — `conversation_inactivity`

1. Template `message` (`MessageTemplates::Template::AutoResolve`)
2. `actions[]` em ordem
3. `resolve_on_match` ou ação `resolve_conversation`

### 3.5 Ordem — `agent_no_reply`

1. `actions[]` em ordem
2. Resolve só se ação explícita

---

## 4. Deduplicação

| Trigger | Chave |
|---------|-------|
| `agent_no_reply`, `first_response_overdue` | `(rule_id, conversation_id, waiting_since_epoch)` |
| `conversation_inactivity`, `pending_stale`, `unassigned_too_long`, `customer_no_reply` | `(rule_id, conversation_id, last_activity_epoch)` |

- Tabela: `conversation_workflow_rule_executions` (índices parciais únicos)
- Reset: novo episódio (novo epoch) → nova chave
- `unassigned_too_long`: ao assignar, `clear_unassigned_too_long_for!` limpa executions da conversa

## 4.1 Runtime: per-message vs cron

| Trigger | Per-message | Cron |
|---------|:-----------:|:----:|
| `agent_no_reply`, `first_response_overdue` | ✅ incoming | ✅ |
| `customer_no_reply` | ✅ outgoing | ✅ |
| `conversation_inactivity`, `unassigned_too_long`, `pending_stale` | ❌ | ✅ |
| Qualquer + `respect_business_hours` | ❌ | ✅ |

Business hours não agenda Sidekiq delay — só o cron de 5 min avalia elapsed útil.
---

## 5. Legacy e coexistência

| Mecanismo | Regra |
|-----------|-------|
| `accounts.settings.auto_resolve_*` | Migrar para regra; manter leitura 1 release |
| `workflow_rules_migrated_at` | Quando setado, **skip** `Conversations::ResolutionJob` para a conta |
| Período transição | Nunca rodar legacy + novo scheduler na mesma conta |
| `auto_resolve_ignore_waiting` | = regra inatividade + `ignore_waiting: true` |

---

## 6. Auditoria e UX

| Item | Regra |
|------|-------|
| Activity messages | Identificar regra via `Current.executed_by` |
| i18n | `conversations.activity.workflow_rule.*` (en + pt_BR) |
| UI unattended | Link “afeta fila Não atendidas” + preview count (Fase 2.5) |

---

## 7. Outros módulos

| Módulo | Comportamento |
|--------|---------------|
| Automação `conversation_resolved` | Dispara após resolve automático |
| Required attributes | Fase 4: backend via `ResolveService`; sistema usa `skip_required_attributes` |
| Captain pending job | Escopo separado — não alterar Fase 1–3 |
| SLA Enterprise | **Distinto** — SLA = compromisso contratual (prazos, métricas, políticas Enterprise); workflow = automação operacional por regra de conta. Não compartilham tabela nem scheduler. |
| Business hours | Implementado — `BusinessHoursElapsedCalculator`; pausar contagem via `inbox.working_hours` (opt-in `respect_business_hours` por regra) |

---

## 8. Permissões e feature flags

| Flag | Gatilho |
|------|---------|
| `auto_resolve_conversations` | `conversation_inactivity`, `customer_no_reply` |
| `conversation_agent_no_reply_rules` | `agent_no_reply`, `first_response_overdue`, `unassigned_too_long`, `pending_stale` |
| `conversation_required_attributes` | Inalterado |

Config: **administrator**.

---

## 9. Validações

| Campo | Regra |
|-------|-------|
| `name` | Obrigatório, max 255 |
| `duration_minutes` | 10 .. 1_439_856 |
| `inbox_ids` | IDs da conta |
| `actions` | Whitelist + validação espelhada de `AutomationRule` |
| `conditions` | Atributos permitidos por fase |

---

## 10. Runtime (matriz)

```
Cron (*/5) e/ou ScheduleOnMessageJob:
  Para cada conta com regras ativas:
    Para cada regra (position ASC):
      IF NOT feature_flag(trigger_type) → skip
      scope = Scope do trigger (+ inbox_ids, cutoff se calendar time)
      conversations = scope.limit(BULK_ACTIONS_LIMIT)
      Para cada conversa:
        IF ScopeMatcher / ThresholdMatcher falha → skip
        IF conditions present → ConditionsFilterService
        IF claim_execution! falha (dedup) → skip
        ConversationWorkflow::ActionService.perform(actions)
        IF inactivity + resolve_on_match → ResolveService
        Activity message + AutomationEventDispatcher
```

---

*Última atualização: ago/2026 — ação `send_message_to_contact` (inbox + contato + template)*
