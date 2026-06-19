# Plano consolidado — Pesquisa de mensagens na conversa

Este é o **documento normativo** da feature. Os demais arquivos desta pasta preservam investigação, alternativas e referências visuais, mas não substituem as decisões abaixo.

**Reavaliado em:** 19 de junho de 2026

**Estado:** não implementado

---

## 1. Resultado esperado

O agente abre o menu ⋮ da conversa, seleciona **Pesquisar nesta conversa**, digita pelo menos 2 caracteres e recebe resultados de todo o histórico acessível da conversa.

A busca cobre:

- conteúdo de mensagens;
- notas privadas;
- templates;
- transcrições de áudio já persistidas em `attachments.meta`.

Ao selecionar um resultado, a aplicação garante que a mensagem esteja carregada, fecha o dialog, faz scroll e aplica o highlight existente.

---

## 2. Escopo da primeira entrega

A primeira entrega deve ser um único corte vertical pronto para uso. As etapas abaixo são checkpoints de implementação, não releases parciais.

### Incluído

- um endpoint: `GET /api/v1/accounts/:account_id/conversations/:conversation_id/messages/search`;
- autorização herdada de `Conversations::BaseController`;
- busca em texto e transcrição;
- paginação de 15 resultados com `has_more`, sem `COUNT DISTINCT`;
- dialog aberto pelo `MoreActions`;
- estados idle, loading, vazio e erro;
- inserção direta do resultado no histórico quando ele não estiver no DOM;
- scroll e highlight;
- indicador de nota privada e de match em transcrição;
- cancelamento de requests obsoletas com `AbortController`;
- validação de performance com uma conversa grande;
- i18n em inglês, conforme `chatwoot-core.mdc`.

### Não incluído

- OpenSearch ou GIN;
- filtros por remetente/data;
- atalhos globais;
- buscas recentes;
- painel lateral;
- analytics;
- mudanças na pesquisa global;
- specs automatizadas, salvo solicitação explícita.

---

## 3. Decisões consolidadas

| Tema | Decisão |
|------|---------|
| Entrada | Item no menu ⋮, antes de “Enviar transcrição” |
| UI | `components-next/Dialog`, `position="top"`, `width="lg"` |
| Estado | Local no composable; não reutilizar `conversationSearch` |
| API | Endpoint scoped à conversa; não estender `/search/messages` |
| Busca | `ILIKE` em conteúdo e metadados de transcrição |
| Histórico | Sem corte de 3 meses |
| Paginação | 15 por página; buscar 16 e responder `has_more` |
| Scroll | Mesclar diretamente o resultado já retornado pela busca |
| Store | Reutilizar `SET_MISSING_MESSAGES` com array previamente mesclado |
| Highlight | Aplicar temporariamente a classe visual já usada pela bolha |
| Concorrência | Cancelar a request anterior com `AbortController` |
| Notas privadas | Mesma fronteira do endpoint normal de mensagens |
| Memória | Medir crescimento; implementar limite seguro sem poda cega |
| Acentos | Avaliar `unaccent` somente após medição e desenho de índice |
| Fork | Ruby novo em `custom/`; hooks upstream mínimos com `FORK:` |
| Frontend | Arquivos novos na árvore existente do dashboard |
| Traduções | Somente `en/conversation.json` |

---

## 4. Arquitetura mínima

```text
MoreActions
  └── ConversationMessageSearchDialog
        ├── useConversationMessageSearch
        │     └── ConversationMessageSearchAPI
        ├── ConversationMessageSearchResultItem
        └── useScrollToConversationMessage
              ├── SET_MISSING_MESSAGES
              └── SCROLL_TO_MESSAGE

GET messages/search
  └── MessagesController#search (prepend)
        └── Custom::ConversationMessageSearchFinder
```

O service intermediário foi removido do plano. No MVP ele apenas repassaria argumentos ao finder, sem orquestrar outra ação. Se GIN/OpenSearch forem implementados, extrair estratégias nessa ocasião.

---

## 5. Contrato da API

### Request

```http
GET /api/v1/accounts/:account_id/conversations/:conversation_id/messages/search?q=contrato&page=1
```

`conversation_id` é o `display_id`, como nas demais rotas de mensagens.

| Parâmetro | Regra |
|-----------|-------|
| `q` | obrigatório; trim; 2 a 200 caracteres |
| `page` | opcional; inteiro positivo; default 1 |

### Response

```json
{
  "payload": [
    {
      "id": 123,
      "content": "Texto da mensagem",
      "message_type": 0,
      "created_at": 1781800000,
      "private": false,
      "sender": {},
      "attachments": []
    }
  ],
  "meta": {
    "current_page": 1,
    "has_more": true
  }
}
```

| Status | Uso |
|--------|-----|
| `200` | busca concluída, inclusive sem resultados |
| `401/403` | autenticação ou autorização |
| `404` | conversa inexistente |
| `422` | query ou página inválida |

O payload reutiliza `api/v1/models/_message.json.jbuilder`.

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

Antes de considerar o backend pronto:

1. criar ou usar uma conversa representativa, com milhares de mensagens e attachments;
2. executar `EXPLAIN (ANALYZE, BUFFERS)` para:
   - match em `messages.content`;
   - match somente em transcrição;
   - query sem resultados;
3. registrar tempo, plano e quantidade de buffers no PR ou nota de implementação;
4. confirmar que o índice trigram existente em `messages.content` é utilizado quando aplicável;
5. observar que o GIN genérico de `attachments.meta` pode não acelerar `ILIKE` sobre texto extraído.

Não adicionar índice novo sem evidência desta medição.

---

## 7. Frontend

### 7.1 Arquivos novos

```text
app/javascript/dashboard/api/conversationMessageSearch.js
app/javascript/dashboard/composables/fork/useConversationMessageSearch.js
app/javascript/dashboard/composables/fork/useScrollToConversationMessage.js
app/javascript/dashboard/components/widgets/conversation/ConversationMessageSearch/
├── ConversationMessageSearchDialog.vue
└── ConversationMessageSearchResultItem.vue
```

Não criar um componente `Form` que apenas encapsule um `Input`; isso seria abstração prematura. O dialog orquestra UI e os composables concentram a lógica.

### 7.2 API e busca

`conversationMessageSearch.js` segue o padrão de `ApiClient` existente. O método recebe `signal` e o encaminha ao Axios:

```javascript
search({ conversationId, query, page = 1, signal })
```

`useConversationMessageSearch` mantém:

- `query`;
- `results`;
- `currentPage`;
- `hasMore`;
- `isSearching`;
- `error`;
- debounce de 500 ms;
- um `AbortController` para a request atual;
- cancelamento físico da request anterior ao mudar query, conversa ou fechar o dialog;
- proteção lógica adicional contra respostas antigas;
- reset ao trocar de conversa ou query;
- append ao carregar mais, sem duplicar IDs.

Não fazer request com menos de 2 caracteres.

Cancelamento por `AbortController` não é erro de UI: não mostrar toast quando Axios indicar request cancelada.

O composable preserva o payload original em snake_case para eventual merge no Vuex. O `ResultItem` cria apenas uma visão camelCase para renderização; não substituir o objeto bruto que veio da API.

### 7.3 Dialog

O dialog:

- expõe `open()` e `close()`;
- recebe foco no input ao abrir;
- fecha com Esc/click outside pelo comportamento do `Dialog`;
- mostra hint para query curta;
- apresenta loading, vazio e erro;
- mantém resultados em uma área com scroll;
- desabilita nova seleção enquanto estiver localizando uma mensagem;
- usa somente Tailwind e strings i18n.

Não é necessário alterar `MessagesView` para mostrar loading. O item selecionado mantém estado de carregamento no dialog enquanto a mensagem é inserida; o dialog fecha assim que o salto pode ser executado.

### 7.4 Resultado

O item mostra:

- autor;
- timestamp;
- snippet com highlight;
- badge de nota privada;
- badge de microfone quando a query corresponde à transcrição.

Para áudio, usar `readTranscriptText`. Não depender da leitura snake_case de attachments em `MessageContent` depois de `useCamelCase`.

Inferência do match:

1. verificar se `message.content` contém a query;
2. verificar transcrição dos attachments de áudio;
3. mostrar badge de transcrição quando houver match na transcrição, mesmo que também exista conteúdo.

Não é necessário adicionar `matched_on` ao contrato MVP.

### 7.5 Integração no menu

Alterar `MoreActions.vue` com blocos `// FORK:` autocontidos:

- import do dialog;
- `ref`;
- item `search_in_conversation`;
- branch no `handleActionClick`;
- instância do dialog no template.

Não remover a prop ignorada de `ConversationHeader` nem limpar `ConversationView` nesta entrega: são débitos independentes e aumentariam a superfície de conflito.

---

## 8. Salto robusto para a mensagem

O resultado da busca já usa o mesmo partial de mensagem do histórico, portanto uma segunda request é desnecessária no caminho normal.

`useScrollToConversationMessage` recebe a **mensagem bruta selecionada** e executa:

1. Se `#message{id}` existe, seguir ao passo 5.
2. Mesclar a mensagem selecionada com as mensagens atuais por ID e ordenar por `created_at`.
3. Commitar o array completo com a mutation existente `SET_MISSING_MESSAGES`.
4. Aguardar render (`nextTick`) e confirmar novamente que o elemento existe.
5. Fechar o dialog e emitir `BUS_EVENTS.SCROLL_TO_MESSAGE`.
6. Adicionar `bg-n-alpha-1` ao elemento e removê-la após 1 segundo. Essa é a mesma classe usada pelo highlight atual da bolha e evita alterar a URL ou o componente upstream.
7. Se o alvo não existir após o merge, manter/fechar o dialog de forma consistente e exibir `MESSAGE_NOT_FOUND`; nunca emitir o evento que cairia em `scrollToBottom()`.

Com isso, não são necessários:

- `INSERT_MESSAGES_AROUND`;
- novo mutation type;
- alteração em `MessagesView`;
- alteração em `Message.vue`;
- `route.query.messageId`;
- segunda request de mensagens;
- janela arbitrária `messageId ± 100`.

Ao mesclar, ler o estado mais recente imediatamente antes do commit para reduzir disputa com mensagens recebidas em tempo real.

### 8.1 Limite de crescimento no Vuex

Saltos repetidos não devem fazer o histórico crescer sem limite.

No MVP:

- medir o tamanho de `chat.messages` após uma sequência manual de pelo menos 100 saltos;
- confirmar que cada salto adiciona no máximo uma mensagem;
- não implementar poda cega por tamanho do array.

Pós-MVP, antes de adicionar atalhos que aumentem muito o uso:

- manter um registro por conversa dos IDs que **não estavam no store** e foram inseridos pela busca;
- limitar esse registro, inicialmente, a 50 mensagens;
- ao ultrapassar o limite, remover primeiro os IDs de busca mais antigos, protegendo alvo atual e mensagens visíveis;
- retirar um ID do registro quando ele passar a fazer parte de uma página normal carregada;
- limpar o registro ao trocar/limpar a conversa selecionada.

Essa melhoria exige integração com o carregamento normal de páginas para distinguir proveniência. Não ampliar hooks upstream no MVP apenas para implementar a poda.

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

| Cenário | Esperado |
|---------|----------|
| Query com 0–1 caractere | nenhuma request; hint visível |
| Texto em mensagem recente | resultado, scroll e highlight |
| Texto em mensagem antiga | mescla o resultado, scrolla e destaca |
| Termo só em transcrição Groq | resultado com snippet e mic |
| Termo na chave legada `transcribed_text` | resultado |
| Áudio sem transcrição | não aparece pelo áudio |
| Nota privada | aparece com badge |
| Mensagem activity | não aparece |
| Mensagem deletada | não aparece |
| Vários attachments no mesmo message | um resultado |
| Página com 16+ matches | devolve 15 e `has_more: true` |
| Última página | `has_more: false`; botão desaparece |
| Página seguinte | append sem duplicação e sem `COUNT` |
| Query muda durante request | request anterior é abortada sem toast |
| Resposta antiga chega depois da nova | não sobrescreve a query atual |
| Resultado fora do DOM | merge direto; nenhuma segunda request |
| 100 saltos para itens isolados | no máximo 100 mensagens adicionadas; crescimento registrado |
| Resultado sem ID/elemento após merge | alerta; sem scroll para o fim |
| Conversa sem acesso | 403/404 conforme controller base |
| Agente autorizado vê nota privada | resultado igual ao endpoint normal de mensagens |
| Viewport estreito | dialog sem overflow horizontal |

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

Objetivo futuro: `contrato` localizar `contráto` e vice-versa.

Não incluir no MVP porque o banco possui `pg_trgm`, mas não possui `unaccent` habilitado. Aplicar `unaccent()` diretamente sem índice funcional pode degradar a busca.

Antes de implementar:

1. confirmar idiomas e comportamento desejado;
2. avaliar extensão `unaccent`;
3. comparar coluna normalizada, índice funcional trigram e normalização na escrita;
4. medir impacto em conteúdo e transcrições;
5. preparar migração concorrente e estratégia de rollback.

---

## 14. Pós-MVP priorizado

1. Finalizar limite de mensagens injetadas, caso o checkpoint seguro tenha ficado fora do MVP.
2. Busca sem acentos com índice compatível.
3. Atalho `Ctrl/Cmd+F` e command bar.
4. Filtro por remetente/tipo.
5. Assunto de e-mail e melhor identificação da origem do match.
6. GIN/OpenSearch scoped por `conversation_id`.
7. Navegação por teclado nos resultados.
8. Limite máximo global de resultados.
9. Painel lateral somente se feedback indicar que o dialog prejudica o contexto.

Não extrair estratégia de busca, predicate compartilhado ou store dedicado antes de uma dessas necessidades existir.
