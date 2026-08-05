# Automation `opened_by` — Regras de negócio

## 1. Definições

| Papel | Significado no produto |
|-------|------------------------|
| **Destino / Contato** | Cliente no WhatsApp (ou outro canal) |
| **Origem — Agente** | Usuário do Chatwoot (dashboard): criar conversa ou **Reabrir** |
| **Origem — Phone** | WhatsApp conectado no Chatwoot usado no **celular** ou **WhatsApp Web** (`fromMe` / `phone_sent` / `external_echo`) |

O menu de boas-vindas deve sair **somente** quando o **contato** inicia a interação (criação ou reabertura).

---

## 2. Valor `opened_by`

Persistido em `conversation.additional_attributes['opened_by']`.

| Valor | Quando |
|-------|--------|
| `contact` | Mensagem **incoming** cria conversa ou reabre (resolved/snoozed/pending → open/pending) |
| `agent` | Agente cria conversa pela API/dashboard, ou altera status para `open` (ex.: botão Reabrir) |
| `phone` | Sync de mensagem enviada pelo aparelho/Web da origem (`PhoneOutgoingSyncService`, echo Meta) |

Uma única chave: na **reabertura**, o valor é **sobrescrito** para refletir quem causou o episódio atual.

---

## 3. Quando stamp (e quando não)

### Stamp

- Create via `Conversations::Resolver` com `Current.conversation_opened_by` ou `additional_attributes` explícito
- WhatsApp inbound (`IncomingMessageServiceHelpers`) → `contact` (ou `phone` se `outgoing_echo`)
- Evolution / Evolution Go phone outgoing sync → `phone`
- `ConversationsController#create` → `agent`
- Reopen por mensagem incoming → `contact` **antes** de `open!` / `pending!`
- `toggle_status` / status → `open` por `User` → `agent`
- Wavoip: reopen inbound (`pending`) → `contact`; reopen outbound (`open`) → `agent`
- Wavoip/Voice: create outbound linker → `agent`; create inbound call builder → `contact`

### Não stamp

- Mensagem outgoing “normal” do dashboard em conversa já aberta (não é create/reopen)
- Phone sync em conversa **já existente** resolvida com lock single (outgoing não chama reopen de Message)
- `history_import`
- Conversas antigas sem valor (não inventar `contact` por default)
- Widget / API pública de create (ainda sem hook explícito)
- Regras delayed de conversa **não** podem usar `opened_by` (allowlist continua `status` + `inbox_id`)

---

## 4. Automação

### Eventos com a condição na UI

- `conversation_created`
- `conversation_opened`

### Operadores

`equal_to`, `not_equal_to`, `is_present`, `is_not_present`

### Configuração recomendada (boas-vindas)

| Condição | Valor |
|----------|-------|
| Caixa de entrada | WhatsApp (ou inbox desejada) |
| Agente atribuído | Não está presente *(opcional, como hoje)* |
| **Aberto por** | **Igual a Contato** |

### Compatibilidade

- Regra **sem** condição `opened_by` → comportamento anterior (qualquer abertura pode casar).
- Regra **com** `opened_by = contact` → só episódios stampados como contato.

---

## 5. Relação com outros produtos

| Produto | Relação |
|---------|---------|
| Automação clássica | Consome a condição |
| Regras de conversa (workflow) | Não altera; pode reutilizar o atributo no futuro se necessário |
| `performed_by` / `Current.executed_by` | Ephemeral em eventos; **não** substitui `opened_by` persistido |

---

## 6. Critérios de aceite

1. Contato manda 1ª msg → `opened_by=contact` → boas-vindas com filtro disparam.
2. Origem manda 1ª msg pelo WhatsApp Web → `opened_by=phone` → boas-vindas com filtro **não** disparam.
3. Agente clica Reabrir → `opened_by=agent` → boas-vindas com filtro **não** disparam.
4. Contato manda msg em conversa resolvida → reopen + `contact` → boas-vindas com filtro disparam.
5. Regra “reatribuir agente” (`conversation_updated`) inalterada (sem a condição na UI desse evento).
