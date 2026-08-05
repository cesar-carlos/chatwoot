# Automation message variables — Regras de negócio

## 1. Onde se aplica

| Ação da Automação | Variáveis |
|-------------------|-----------|
| Enviar mensagem | Sim (Liquid no create outgoing) |
| Adicionar nota privada | Sim (mesma mensagem outgoing/private) |
| Outras ações | Fora do escopo deste feature |

Macros que reutilizam `AutomationActionInput` com `textarea` herdam a mesma UX de chips.

## 2. Interpolação

- Placeholders `{{...}}` são salvos no `action_params` da regra.
- Na execução, `AutomationRules::ActionService` cria a mensagem; `Liquidable` renderiza com drops da **conversa da automação**.
- Sintaxe Liquid (filtros como `default`) continua válida.

## 3. Variáveis expostas (chips / menu)

| Chave | Origem |
|-------|--------|
| `conversation.id` | display_id (Liquid) |
| `conversation.display_id` | display_id |
| `contact.name` / `first_name` / `last_name` / `email` / `phone_number` | ContactDrop |
| `contact.phone` | Alias FORK → `phone_number` |
| `agent.name` | assignee (sender nil na automação) |
| `inbox.name` | InboxDrop |
| `account.name` | AccountDrop |
| `rule.name` | AutomationRule **ou** ConversationWorkflowRule |
| `macro.name` | Macro (só em macros) |
| `*.custom_attribute.*` | Menu `{{` via VariableList |
| Filtros | Ex.: `contact.email \| default: "sem email"` |

## 4. Diferença vs regras de conversa

| | Automação | Workflow `send_message_to_contact` |
|--|-----------|-------------------------------------|
| Motor | Liquid | Liquid (unificado; contexto = conversa **trigger**) |
| Destino | Mesma conversa | Outro contato/inbox |
| Contexto contact | Contato da conversa | Contato da conversa **trigger** |

## 5. Critérios de aceite

1. No formulário de Automação, ações de mensagem mostram chips e prévia.
2. Mensagem com `{{contact.name}}` e `{{rule.name}}` interpola na execução.
3. `{{contact.phone}}` e `{{contact.phone_number}}` resolvem o telefone.
4. Regras sem placeholders continuam iguais.
