# Automation `opened_by` — Regras de negócio

## 1. Definições

| Papel | Significado no produto |
|-------|------------------------|
| **Destino / Contato** | Cliente no canal (WhatsApp, e-mail, Telegram, SMS, Line, Twilio, Instagram, Facebook, TikTok, Twitter, widget, API pública, chamada inbound) |
| **Origem — Agente** | Usuário do Chatwoot: criar conversa, **Reabrir**, ou responder em conversa resolved/snoozed |
| **Origem — Phone** | WhatsApp conectado no Chatwoot usado no **celular** ou **WhatsApp Web** (`fromMe` / `phone_sent` / `external_echo`) |

O menu de boas-vindas deve sair **somente** quando o **contato** inicia a interação (criação ou reabertura).

---

## 2. Valor `opened_by`

Persistido em `conversation.additional_attributes['opened_by']`.

| Valor | Quando |
|-------|--------|
| `contact` | Mensagem **incoming** cria a conversa ou reabre (resolved/snoozed → open/pending); widget; API pública; chamada de voz inbound; e-mail, Telegram, SMS, Line, Twilio, Instagram, Facebook, TikTok e Twitter inbound |
| `agent` | Agente cria pela API do dashboard, promove pending → open, muda o status para `open`, responde em resolved/snoozed, inicia chamada outbound, ou uma regra de fluxo cria a conversa para mandar mensagem ao contato. Tweet/DM enviado pela conta conectada também grava `agent` na criação |
| `phone` | Sync de mensagem enviada pelo aparelho/Web da origem, ou echo de Instagram, Facebook e TikTok, na criação. No histórico único, a mensagem do celular em conversa resolved/snoozed reabre o episódio como `phone` |

Uma única chave: na **reabertura**, o valor é **sobrescrito** para refletir quem causou o episódio atual.

Conversa sem a chave (legado ou canal ainda sem hook) não casa com `equal_to contact`. A leitura não inventa `contact`.

---

## 3. Quando stamp (e quando não)

### Stamp

- Create via `Conversations::Resolver` com `Current.conversation_opened_by` ou `additional_attributes` explícito. O explícito ganha.
- WhatsApp inbound → `contact` (ou `phone` se `outgoing_echo`)
- Evolution / Evolution Go phone outgoing sync → `phone` na criação. Se a inbox tem histórico único e a conversa está resolved ou snoozed, reabre como `phone` antes da mensagem
- Dashboard `ConversationsController#create` / `AgentStartService` → `agent`
- Compose do agente em resolved/snoozed ou pending → `agent` antes do `open!`
- Reopen por mensagem incoming em resolved/snoozed → `contact` **antes** de `open!` / `pending!`
- Reopen por mensagem **outgoing humana** do dashboard em resolved/snoozed → `agent`
- `toggle_status` para `open` por `User`, só se a conversa ainda não está aberta → `agent`
- Wavoip: reopen inbound (`pending`) → `contact`; reopen outbound (`open`) → `agent`
- Voz: create outbound → `agent`; create inbound → `contact`
- Widget `POST /api/v1/widget/conversations` → `contact`
- API pública `POST /public/api/v1/inboxes/.../conversations` → `contact` (atributo enviado pelo cliente é ignorado)
- E-mail IMAP, Telegram, SMS, Line, Twilio, Instagram, Facebook, TikTok e Twitter inbound → `contact` na criação. Echo desses canais sociais → `phone`
- Fluxo de conversa `send_message_to_contact`, quando cria a conversa → `agent`

### Não stamp

- Resposta do contato enquanto a conversa **já está pending** com `opened_by` `phone` ou `agent` (o episódio continua de quem abriu; a segunda mensagem do ciclo Evolution pode abrir, mas não troca o valor)
- Outgoing do dashboard em conversa **já aberta**
- Nota privada, campanha, mensagem de automação (`automation_rule_id`), echo (`external_echo`) e chamada de voz no `AgentOutgoingReopen`
- Phone sync em conversa **já aberta ou pending** (não troca o episódio)
- Phone sync em conversa resolved **sem** histórico único: abre uma conversa nova com `phone`; a resolvida fica como estava
- `history_import`
- Conversas antigas sem valor, até `bundle exec rake opened_by:backfill` (opcional `ACCOUNT_ID`)
- Regras delayed de conversa: a allowlist continua `status` + `inbox_id`

### Ciclo Evolution `conversation_pending`

Com a opção ligada, a primeira incoming em conversa resolved/snoozed (ou a criação) deixa o status `pending` e grava `opened_by=contact`.

`conversation_opened` só existe quando o status fica `open`. A regra **Conversa Aberta** espera a **segunda** mensagem do contato. A regra **Conversa Criada** já vê `contact` na primeira mensagem de uma conversa nova.

Se o episódio pending já é `phone` ou `agent`, a resposta do contato não troca o valor. A segunda mensagem pode abrir a conversa, e **Conversa Aberta** continua vendo quem abriu.

---

## 4. Automação

### Eventos com a condição na UI

- `conversation_created`
- `conversation_opened`
- `message_created`

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
| Regras de conversa (workflow) | Condição `opened_by` na allowlist e no formulário |
| Lista de conversas | Filtro **Aberto por** no filtro avançado |
| Relatório ao vivo | Contagem de episódios abertos e pending por `contact`, `agent`, `phone` e sem valor |
| `performed_by` / `Current.executed_by` | Efêmero no evento; não substitui `opened_by` persistido |
| `phone_sent` / `external_echo` na mensagem | Marca a origem daquela mensagem; `opened_by=phone` é o episódio da conversa |

---

## 6. Critérios de aceite

1. Contato manda a 1ª msg no WhatsApp → `opened_by=contact` → boas-vindas com filtro disparam em **Conversa Criada**.
2. Origem manda a 1ª msg pelo WhatsApp Web → `opened_by=phone` → boas-vindas com filtro **não** disparam.
3. Agente clica Reabrir, ou responde em conversa resolvida → `opened_by=agent` → boas-vindas com filtro **não** disparam.
4. Contato manda msg em conversa resolvida → reopen + `contact` → boas-vindas com filtro disparam em **Conversa Aberta** (na segunda msg, se `conversation_pending` estiver ligado).
4b. Episódio já `pending` com `opened_by=phone` (ou `agent`) → resposta do contato **não** troca para `contact`. Com `conversation_pending`, a abertura na segunda mensagem continua `phone` e o menu **não** sai.
5. Contato abre pelo widget, pela API pública, e-mail, Telegram, SMS ou rede social → `opened_by=contact`.
5b. Celular manda mensagem numa conversa resolved com histórico único → reabre com `opened_by=phone`.
6. Regra de reatribuir agente (`conversation_updated`) permanece sem essa condição na UI.
