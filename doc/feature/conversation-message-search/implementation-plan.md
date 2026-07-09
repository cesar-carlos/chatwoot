# Plano consolidado — Pesquisa de mensagens na conversa

Este é o **documento normativo** da feature. Os demais arquivos desta pasta preservam investigação, alternativas e referências visuais, mas não substituem as decisões abaixo.

**Reavaliado em:** 9 de julho de 2026

**Estado:** implementado (MVP + melhorias P1/P2 — ver §14). As secções §1–§4 e §7–§8 abaixo refletem o **estado vigente no código**, não o rascunho MVP original.

---

## 1. Resultado esperado

O agente abre a pesquisa via menu ⋮, lupa do painel lateral, ⌘F / Ctrl+F ou command bar, digita pelo menos 2 caracteres e recebe resultados de todo o histórico acessível da conversa.

A busca cobre:

- conteúdo de mensagens;
- assunto de e-mail (`content_attributes.email.subject`);
- notas privadas;
- templates;
- transcrições de áudio já persistidas em `attachments.meta`.

Ao selecionar um resultado, a aplicação garante que a mensagem esteja carregada, fecha o painel, faz scroll e aplica o highlight existente.

---

## 2. Escopo entregue

Entrega vertical pronta para uso (checkpoints históricos A–C + P1/P2 selecionados).

### Incluído

- endpoint `GET .../messages/search` com `q`, `page`, `from`;
- autorização herdada de `Conversations::BaseController`;
- busca em texto, assunto de e-mail e transcrição;
- motores ILIKE / unaccent / GIN / OpenSearch (com fallback SQL);
- paginação de 15 resultados com `has_more`, `max_results` 100;
- painel lateral (`ConversationMessageSearchPanel`) + menu ⋮ / ⌘F / command bar;
- filtros remetente, buscas recentes, infinite scroll, analytics;
- `INSERT_MESSAGES_AROUND` + poda de mensagens injetadas (50);
- scroll, highlight, `AbortController`, rate limit;
- i18n `en` (e locales fork `pt` / `pt_BR`);
- specs RSpec + Vitest.

### Fora de escopo / pendente operacional

- `EXPLAIN` em conversa grande de produção;
- matriz de aceite §11 cenários manuais restantes;
- reindex OpenSearch em contas com índice antigo (ver rake `reindex_hints`).

---

## 3. Decisões consolidadas (vigentes)

| Tema | Decisão |
|------|---------|
| Entrada | Menu ⋮, `SidepanelSwitch`, ⌘F / Ctrl+F, command bar |
| UI | Painel lateral `ConversationMessageSearchPanel` (não Dialog) |
| Estado | Local no composable; não reutilizar `conversationSearch` |
| API | Endpoint scoped à conversa; não estender `/search/messages` |
| Busca | ILIKE (+ unaccent) / GIN / OpenSearch em content, subject e transcrição |
| Histórico | Sem corte de 3 meses |
| Paginação | 15 por página; buscar 16 e responder `has_more`; teto 100 |
| Scroll | Injetar resultado via `INSERT_MESSAGES_AROUND`; fallback `getPreviousMessages` |
| Store | Mutations fork + registry/poda de IDs injetados pela busca |
| Highlight | Classe temporária na bolha; `prefers-reduced-motion` → ring |
| Concorrência | Cancelar a request anterior com `AbortController` |
| Notas privadas | Mesma fronteira do endpoint normal de mensagens |
| Memória | Poda de até 50 mensagens injetadas por conversa |
| Acentos | Extensão `unaccent` + índice funcional GIN trigram |
| Fork | Ruby novo em `custom/`; hooks upstream mínimos com `FORK:` |
| Frontend | Arquivos novos + composables em `composables/fork/` |
| Traduções | `en/conversation.json` (obrigatório); `pt`/`pt_BR` no fork |

---

## 4. Arquitetura vigente

```text
MoreActions / SidepanelSwitch / ⌘F
  └── ConversationMessageSearchPanel
        └── ConversationMessageSearchView
              ├── useConversationMessageSearch
              │     └── ConversationMessageSearchAPI
              ├── ConversationMessageSearchResultItem
              └── useScrollToConversationMessage
                    ├── INSERT_MESSAGES_AROUND
                    ├── REGISTER / PRUNE_SEARCH_INJECTED
                    ├── MessageApi.getPreviousMessages (fallback)
                    └── SCROLL_TO_MESSAGE

GET messages/search
  └── MessagesController#search (prepend)
        └── Custom::ConversationMessageSearchFinder
              ├── MatchingIds / ContentPredicate (SQL)
              └── Message.search (OpenSearch, se advanced_search)
```

Sem service intermediário: o controller valida params e delega ao finder.

---

## 5. Contrato da API

### Request

```http
GET /api/v1/accounts/:account_id/conversations/:conversation_id/messages/search?q=contrato&page=1&from=contact
```

`conversation_id` é o `display_id`, como nas demais rotas de mensagens.

| Parâmetro | Regra |
|-----------|-------|
| `q` | obrigatório; trim; 2 a 200 caracteres |
| `page` | opcional; inteiro positivo; default 1 |
| `from` | opcional; `contact` \| `agent` \| `private` \| `contact:N` \| `agent:N` |

### Response

```json
{
  "payload": [
    {
      "id": 123,
      "content": "Texto da mensagem",
      "matched_on": "content",
      "message_type": 0,
      "created_at": 1781800000,
      "private": false,
      "sender": {},
      "attachments": []
    }
  ],
  "meta": {
    "current_page": 1,
    "has_more": true,
    "max_results": 100,
    "search_engine": "ilike_unaccent"
  }
}
```

| Status | Uso |
|--------|-----|
| `200` | busca concluída, inclusive sem resultados |
| `401/403` | autenticação ou autorização |
| `404` | conversa inexistente |
| `422` | query ou página inválida |
| `429` | rate limit (30 req/min por user+conversa) |

O payload reutiliza `api/v1/models/_message.json.jbuilder` + `matched_on` opcional.

---

## 6. Backend

### 6.1 Finder único

**Arquivo:** `custom/app/finders/custom/conversation_message_search_finder.rb`

Responsabilidades:

- partir de `conversation.messages`;
- validar/normalizar apenas valores já aceitos pelo controller;
- excluir `activity`;
- excluir mensagens marcadas como deletadas;
- pesquisar `messages.content`;
- pesquisar somente attachments de áudio em:
  - `meta->>'transcribed_text'`;
  - `meta->'transcription'->>'text'`;
- aplicar `distinct`;
- ordenar por `messages.created_at DESC`;
- eager load de `attachments` e `sender`;
- aplicar offset da página;
- buscar `PER_PAGE + 1`;
- remover o item excedente e expor `has_more`.

Usar `ActiveRecord::Base.sanitize_sql_like(query.strip)`, não um escape manual.

Forma esperada da query:

```ruby
conversation.messages
            .left_joins(:attachments)
            .where(message_type: %i[incoming outgoing template])
            .where("COALESCE(messages.content_attributes->>'deleted', 'false') != 'true'")
            .where(search_predicate, pattern: "%#{escaped_query}%", audio_type: Attachment.file_types[:audio])
            .distinct
            .reorder(created_at: :desc)
            .includes(:attachments, :sender)
            .offset((page - 1) * PER_PAGE)
            .limit(PER_PAGE + 1)
```

Ao implementar, confirmar a expressão com registros cujo `content_attributes` seja `NULL`, `{}` e `{ "deleted": true }`.

O finder pode expor `has_more?` após `perform`, mantendo o retorno principal como coleção de até 15 mensagens. Não executar `count`, `total_count` ou paginação Kaminari neste endpoint.

**Implementação:** usa subquery `SELECT DISTINCT messages.id` + fetch externo em vez de `SELECT DISTINCT messages.*`, porque `content_attributes` é tipo `json` no PostgreSQL (sem operador de igualdade para `DISTINCT` em linha completa). Comportamento equivalente ao plano.

### 6.1.1 Baseline de performance (checkpoint 1)

Executado em dev local (conversa pequena, ~40 mensagens). Em datasets maiores, repetir com `bundle exec rails search:setup_test_data` ou conta seedada.

```bash
eval "$(rbenv init -)"
bundle exec rails runner "
  c = Conversation.first
  pattern = '%test%'
  audio_type = Attachment.file_types[:audio]
  ids_sql = c.messages.left_joins(:attachments)
    .where(message_type: %i[incoming outgoing template])
    .where(\"COALESCE(messages.content_attributes->>'deleted', 'false') != 'true'\")
    .where(<<~SQL.squish, pattern: pattern, audio_type: audio_type)
      messages.content ILIKE :pattern
      OR (attachments.file_type = :audio_type AND attachments.meta->>'transcribed_text' ILIKE :pattern)
      OR (attachments.file_type = :audio_type AND attachments.meta->'transcription'->>'text' ILIKE :pattern)
    SQL
    .select('messages.id').distinct.reorder(nil).to_sql
  sql = c.messages.where(\"id IN (#{ids_sql})\").reorder(created_at: :desc).limit(16).to_sql
  ActiveRecord::Base.connection.execute(\"EXPLAIN (ANALYZE, BUFFERS) #{sql}\").values.flatten.each { puts _1 }
"
```

| Cenário | Tempo (dev local) | Observação |
|---------|-------------------|------------|
| Match em `content` | ~0,11 ms | Seq scan esperado em N pequeno; índice GIN trigram em `messages.content` relevante em conversas grandes |
| Sem resultados | sub-ms | Hash join + filtro |
| Match só transcrição | medir em conta com áudio transcrito | `attachments.meta` JSONB — GIN genérico pode não acelerar `ILIKE` em texto extraído |

Não adicionar índice novo sem evidência em conversa representativa (milhares de mensagens).

### 6.2 Notas privadas e autorização

Notas privadas permanecem incluídas. Esta decisão foi validada contra o comportamento atual:

- `Conversations::BaseController` autoriza `show?` para a conversa;
- `MessageFinder` inclui mensagens privadas por padrão;
- a exclusão só ocorre quando `filter_internal_messages` é explicitamente enviado.

A busca deve espelhar o endpoint normal de mensagens. Não criar uma regra administrativa paralela no finder. Se a política upstream mudar, ambos os endpoints devem ser ajustados juntos.

### 6.3 Controller por prepend

**Novo:** `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb`

O módulo adiciona somente:

- `search`;
- `search_params`;
- validação explícita de `q` e `page`.

O controller recebe valores primitivos e delega ao finder. A autorização não é duplicada: `Conversations::BaseController#conversation` já localiza a conversa no account e executa `authorize @conversation, :show?`.

**Hook upstream mínimo:**

```ruby
# FORK: load in-conversation message search action
Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with(
  'Api::V1::Accounts::Conversations::MessagesController'
)
```

### 6.4 Rota

Dentro de `resources :messages`:

```ruby
# FORK: in-conversation message search
collection { get :search }
```

### 6.5 View

**Novo:** `app/views/api/v1/accounts/conversations/messages/search.json.jbuilder`

Este é uma exceção consciente ao overlay: `custom/app/views` não está no view path atual. Não alterar `config/application.rb` apenas para um template.

A view contém:

- `payload` usando o partial de mensagem existente;
- `meta.current_page`;
- `meta.has_more`.

`has_more` elimina o `COUNT DISTINCT` que seria necessário para `total_pages` e `total_count`. O produto só precisa saber se deve mostrar **Carregar mais**.

### 6.6 Baseline de performance

Ver §6.1.1 para script `EXPLAIN (ANALYZE, BUFFERS)` e resultados iniciais em dev local.

Antes de considerar o backend pronto em **produção**:

1. criar ou usar uma conversa representativa, com milhares de mensagens e attachments;
2. executar `EXPLAIN (ANALYZE, BUFFERS)` para:
   - match em `messages.content`;
   - match somente em transcrição;
   - query sem resultados;
3. registrar tempo, plano e quantidade de buffers no PR ou nota de implementação;
4. confirmar que o índice trigram existente em `messages.content` é utilizado quando aplicável;
5. observar que o GIN genérico de `attachments.meta` pode não acelerar `ILIKE` sobre texto extraído.

Não adicionar índice novo sem evidência desta medição.

**Status:** script e resultados iniciais documentados em §6.1.1. Repetir em conversa grande antes de merge em produção.

### 7.1 Arquivos

```text
app/javascript/dashboard/api/conversationMessageSearch.js
app/javascript/dashboard/composables/fork/useConversationMessageSearch.js
app/javascript/dashboard/composables/fork/useConversationMessageSearchPanel.js
app/javascript/dashboard/composables/fork/useScrollToConversationMessage.js
app/javascript/dashboard/composables/fork/conversationMessageSearchDisplay.js
app/javascript/dashboard/components/widgets/conversation/ConversationMessageSearch/
├── ConversationMessageSearchPanel.vue
├── ConversationMessageSearchView.vue
└── ConversationMessageSearchResultItem.vue
```

O painel orquestra UI; os composables concentram a lógica.

### 7.2 API e busca

```javascript
search({ conversationId, query, page = 1, from, signal })
```

`useConversationMessageSearch` mantém query, results, paginação, `fromFilter`, recentes (`sessionStorage`), debounce 500 ms, `AbortController`, e append sem duplicar IDs. Sem request com menos de 2 caracteres. Cancelamento não é erro de UI.

### 7.3 Painel

`ConversationMessageSearchPanel` + `ConversationMessageSearchView`:

- foco no input ao abrir; Esc fecha;
- hint, loading, vazio, erro, filtros, recentes, infinite scroll;
- ↑↓ + Enter para navegar/selecionar;
- desabilita seleção enquanto localiza a mensagem.

### 7.4 Resultado

O item mostra autor, timestamp, snippet com highlight, badge de nota privada e badge de microfone em match de transcrição.

Snippet via `buildSearchResultDisplayMessage`: prioriza subject quando o match é só no assunto; usa `readTranscriptText` para áudio; respeita `matched_on` da API (`content` | `transcription`).

### 7.5 Integração

- `MoreActions.vue` — item menu + ⌘F + command bar (`// FORK:`)
- `SidepanelSwitch.vue` + `ConversationView` — painel lateral
- `useConversationMessageSearchPanel` — estado `is_message_search_panel_open`

---

## 8. Salto robusto para a mensagem

`useScrollToConversationMessage` recebe a **mensagem bruta selecionada** e executa:

1. Se `#message{id}` existe, ir ao passo 5.
2. Injetar a mensagem com `INSERT_MESSAGES_AROUND` e registar IDs novos (`REGISTER_SEARCH_INJECTED` + `PRUNE_SEARCH_INJECTED`).
3. Aguardar `nextTick` e reconfirmar o elemento.
4. Se ainda ausente, fallback `MessageApi.getPreviousMessages` com janela `messageId ± 100` e nova injeção.
5. Fechar o painel e emitir `BUS_EVENTS.SCROLL_TO_MESSAGE` **somente** se o elemento existir.
6. Highlight temporário (`bg-n-alpha-1` ou ring se `prefers-reduced-motion`).
7. Se o alvo não existir: toast `MESSAGE_NOT_FOUND`; **não** emitir scroll.

`MessagesView#onScrollToMessage` (FORK): se `messageId` foi pedido e o elemento não está no DOM, **não** faz `scrollToBottom()` — só faz scroll ao fundo quando o evento vem sem `messageId` (comportamento upstream de “ir ao fim”).

### 8.1 Limite de crescimento no Vuex

Saltos repetidos não devem fazer o histórico crescer sem limite.

Implementado:

- registry por conversa dos IDs injetados pela busca (`searchInjectedByConversationId`);
- limite de 50 mensagens; ao ultrapassar, remove os mais antigos protegendo alvo e viewport;
- `DEREGISTER_SEARCH_INJECTED` quando IDs entram via paginação normal (`fetchPreviousMessages`);
- limpar o registry ao trocar/limpar a conversa selecionada.

---

## 9. i18n

Alterar apenas:

`app/javascript/dashboard/i18n/locale/en/conversation.json`

Namespace:

```json
"MESSAGE_SEARCH": {
  "MENU_LABEL": "Search this conversation",
  "TITLE": "Search this conversation",
  "DESCRIPTION": "Find messages in the current conversation history",
  "PLACEHOLDER": "Search messages...",
  "HINT": "Enter at least 2 characters",
  "EMPTY": "No messages found for “{query}”",
  "LOAD_MORE": "Load more",
  "SEARCHING": "Searching messages...",
  "ERROR": "Search failed. Please try again.",
  "MESSAGE_NOT_FOUND": "This message could not be loaded",
  "MATCH_TRANSCRIPTION": "Match in audio transcription",
  "PRIVATE_NOTE": "Private note",
  "OPEN_RESULT": "Open message from {author}, {time}"
}
```

---

## 10. Ordem de implementação

### Checkpoint 1 — Backend verificável

- rota;
- prepend do controller;
- finder;
- Jbuilder;
- validação 422;
- paginação `PER_PAGE + 1` / `has_more`;
- `EXPLAIN (ANALYZE, BUFFERS)` em dataset representativo;
- smoke test manual via request.

### Checkpoint 2 — Busca no dialog

- API client;
- composable;
- dialog;
- result item;
- menu;
- paginação e estados;
- cancelamento real com `AbortController`.

### Checkpoint 3 — Navegação confiável

- composable de scroll;
- merge direto do resultado com mutation existente;
- highlight temporário no elemento;
- erro explícito.

### Checkpoint 4 — Verificação e acabamento

- RuboCop nos arquivos Ruby alterados;
- ESLint nos arquivos Vue/JS alterados;
- teste manual da matriz abaixo;
- inventário de `FORK:` e revisão do diff.

---

## 11. Matriz de aceite

Imprimir checklist: `rake conversation_message_search:acceptance`

| Cenário | Esperado | Auto |
|---------|----------|------|
| Query com 0–1 caractere | nenhuma request; hint visível | Vitest/FE manual |
| Texto em mensagem recente | resultado, scroll e highlight | Manual |
| Texto em mensagem antiga | mescla o resultado, scrolla e destaca | Manual |
| Termo só em transcrição Groq | resultado com snippet e mic | RSpec finder |
| Termo na chave legada `transcribed_text` | resultado | RSpec (estender) |
| Áudio sem transcrição | não aparece pelo áudio | Manual |
| Nota privada | aparece com badge | Manual |
| Mensagem activity | não aparece | RSpec finder |
| Mensagem deletada | não aparece | RSpec finder |
| Assunto de e-mail | resultado com `matched_on: content` | RSpec finder |
| Busca sem acentos (`contrato` ↔ `contráto`) | match com `ilike_unaccent` | RSpec (se extensão ativa) |
| Página com 16+ matches | devolve 15 e `has_more: true` | RSpec finder + HTTP |
| Última página | `has_more: false` | RSpec HTTP page 2 |
| Rate limit | 429 + mensagem UI | RSpec HTTP |
| Viewport estreito | painel sem overflow horizontal | Manual |

---

## 12. Riscos restantes

| Risco | Tratamento |
|-------|------------|
| `ILIKE '%term%'` lento em conversas enormes | medir com `EXPLAIN ANALYZE`; GIN/OpenSearch se necessário |
| Join JSONB de transcrição não usa índice adequado | medir separadamente e desenhar índice funcional/trigram só com evidência |
| Highlight manipula uma classe no elemento | manter a classe já presente no bundle e remover no `finally`/timer |
| Merge concorre com mensagens em tempo real | reler store imediatamente antes do commit e deduplicar |
| Poda remove mensagem útil | rastrear somente IDs inseridos pela busca; proteger alvo, viewport e páginas normais |
| Partial de mensagem acessa associações adicionais | validar N+1 no log; ampliar `includes` somente se observado |

---

## 13. Busca sem acentos

**Implementado** — migração `20260619120000_add_unaccent_for_message_search.rb`:
- extensão `unaccent` + função `unaccent_immutable(text)`
- índice GIN trigram em `unaccent_immutable(content)`
- predicate ILIKE com unaccent em finder e `SearchService` global
- com `search_with_gin` + unaccent ativo, o finder usa ILIKE unaccent (índice trigram) em vez de `to_tsquery`

---

## 14. Pós-MVP priorizado

**Implementado nesta entrega:**
- `matched_on` na API (`content` | `transcription`)
- Filtro `from` (all/contact/agent/private + `contact:N` / `agent:N`)
- Assunto de e-mail no predicate
- `ContentPredicate` partilhado + `SearchService` ILIKE global alinhado
- Rate limit leve (30 req/min por user+conversa)
- Limite 100 resultados (`MAX_RESULTS`)
- ⌘F / Ctrl+F + command bar
- Contador de resultados, hint transcrição, buscas recentes (`sessionStorage`)
- Filtros remetente no dialog
- Navegação ↑↓ + Enter (único resultado salta direto)
- Scroll infinito no dialog
- Poda de mensagens injetadas (50 por conversa)
- `TranscribedText` com highlight
- `prefers-reduced-motion` no highlight
- Remoção de código morto `showSearchModal` em `ConversationView`
- Busca sem acentos (`unaccent` + índice funcional GIN trigram) — migração `20260619120000`
- GIN / OpenSearch scoped por `conversation_id` com fallback SQL
- Painel lateral (`ConversationMessageSearchPanel`) como entrada principal
- Analytics `MESSAGE_SEARCH_EVENTS` (opened, searched, result clicked)
- Specs RSpec expandidos (e-mail, paginação HTTP, `from`, GIN engine)
- Vitest `messageSearchText.spec.js` (fold diacríticos)
- Rake `conversation_message_search:acceptance` (checklist §11)
- GIN com fallback ILIKE em `to_tsquery` inválido; unaccent + `search_with_gin` → ILIKE unaccent
- `SearchService` global: override `filter_messages_with_gin` com transcrição + fallback
- OpenSearch: campo `deleted` no índice + filtro `deleted: false` na query
- OpenSearch: transcrição unificada via `Custom::TranscriptionMetadata.read_text` no `SearchDataPresenter`
- GIN global: assunto de e-mail em `filter_messages_with_gin`
- Poda Vuex de mensagens injetadas (§8.1): `REGISTER/PRUNE/DEREGISTER/CLEAR_SEARCH_INJECTED`
- `MatchedOn` com `fold_text` Ruby (sem round-trips DB)
- Guard `MessagesView#onScrollToMessage` — não faz `scrollToBottom` se `messageId` pedido e elemento ausente
- OpenSearch: over-fetch + skip de hits não pesquisáveis para `has_more` / páginas estáveis
- Snippet de assunto de e-mail no result item (`conversationMessageSearchDisplay`)
- Rake `conversation_message_search:reindex_hints`

**Ainda pendente (validação operacional):**
1. `rake conversation_message_search:explain[conversation_id,query]` em conversa grande (produção) — arquivar plano/tempo
2. Matriz de aceite §11 — cenários manuais restantes (scroll, viewport, áudio sem transcrição)
