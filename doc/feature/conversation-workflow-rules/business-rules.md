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

**Feature flag:** `conversation_agent_no_reply_rules` (nova)

**Ação típica:** escalar — **não** resolver por default.

### 1.3 Semântica de `waiting_since` (importante)

| Fato | Implicação |
|------|------------|
| `before_create :ensure_waiting_since` seta `waiting_since = created_at` | Relógio começa na **criação** da conversa |
| Incoming só seta se `waiting_since` blank | Segundo incoming **não reinicia** o timer |
| Bot/humano responde | Zera `waiting_since` (salvo `preserve_waiting_since`) |
| Nota privada / automação | **Não** zera |

**Filtros opcionais por regra (Fase 2.1):**

- `require_no_first_reply: true` → `first_reply_created_at IS NULL` (“nunca atendida”)
- `statuses: ['open', 'pending']` → incluir pending pós-handoff bot

### 1.4 Matriz comparativa

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

**Fase 3+:** custom attributes de conversa

Duração **não** é condição AND — pertence ao gatilho.

### 2.3 Multi-regra

**Todas** as regras ativas que match executam, na ordem de `position`, salvo dedup.

**Escalonamento em níveis:** criar N regras (ex.: 15 min label, 120 min assign, 1440 min resolve) — cada uma com dedup independente.

---

## 3. Ações

### 3.1 Executor

Usar **`ConversationWorkflow::ActionService`** (não `ActionService` direto):

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

### 3.3 Whitelist

| Ação | Inatividade | Agente não respondeu |
|------|:-----------:|:--------------------:|
| `add_label` / `remove_label` | ✓ | ✓ |
| `add_private_note` | ✓ | ✓ |
| `send_message` | ✓ | ✓ |
| `assign_agent` / `assign_team` | ✓ | ✓ |
| `remove_assigned_agent` / `remove_assigned_team` | ✓ | ✓ |
| `send_webhook_event` | ✓ | ✓ |
| `send_email_to_team` / `send_email_transcript` | ✓ | ✓ |
| `change_priority` | ✓ | ✓ |
| `send_attachment` | ✓ | opcional |
| `resolve_conversation` | ✓ | opcional |
| `snooze` / `open` / `pending` | ✗ | ✗ |

### 3.4 Ordem — `conversation_inactivity`

1. Template `message` (`MessageTemplates::Template::AutoResolve`)
2. `actions[]` em ordem
3. `resolve_on_match` ou ação `resolve_conversation`

### 3.5 Ordem — `agent_no_reply`

1. `actions[]` em ordem
2. Resolve só se ação explícita

---

## 4. Deduplicação

### 4.1 `agent_no_reply`

- Chave: `(rule_id, conversation_id, waiting_since_epoch)`
- Tabela: `conversation_workflow_rule_executions`
- Reset: novo episódio de espera → nova chave

### 4.2 `conversation_inactivity`

- Após `resolve_on_match`, conversa sai do scope
- Alternativa pré-resolve: dedup por `(rule_id, conversation_id, last_activity_at_epoch)`

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
| SLA Enterprise | **Distinto** — SLA = compromisso; workflow = automação operacional |
| Business hours | Fase 4 — pausar contagem via `inbox.working_hours` |

---

## 8. Permissões e feature flags

| Flag | Gatilho |
|------|---------|
| `auto_resolve_conversations` | `conversation_inactivity` |
| `conversation_agent_no_reply_rules` | `agent_no_reply` |
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
Para cada conta com regras ativas:
  Para cada regra (position ASC):
    IF NOT feature_flag(trigger_type) → skip
    scope = InactivityScope | AgentNoReplyScope (+ inbox_ids)
    conversations = scope.limit(BULK_ACTIONS_LIMIT)
    Para cada conversa:
      IF conditions present → ConditionsFilterService
      IF dedup key exists → skip
      ConversationWorkflow::ActionService.perform(actions)
      IF inactivity + resolve_on_match → resolve (ResolveService Fase 4)
      INSERT dedup execution
      Activity message com rule name
```

---

*Última atualização: jun/2026 — melhorias incorporadas*
