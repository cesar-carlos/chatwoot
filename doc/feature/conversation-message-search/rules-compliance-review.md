# Revisão de conformidade — Rules, arquitetura e design

> Documento de apoio à reavaliação. O resultado normativo está no [plano consolidado](./implementation-plan.md).

Reavaliação do levantamento em [current-state.md](./current-state.md) e do plano em [implementation-plan.md](./implementation-plan.md) contra:

- `.cursor/rules/architecture.mdc`
- `.cursor/rules/fork-workflow.mdc`
- `.cursor/rules/chatwoot-core.mdc`
- `.cursor/rules/vue-frontend.mdc`
- Padrões reais do fork (`ShareContact`, `composables/fork`, `components/fork`)

**Data da revisão:** jun/2026

---

## Veredito geral

| Área | Status | Nota |
|------|--------|------|
| Separação backend (service) | ⚠️ Ajustar | Service ok, mas autorização não deve ficar no service |
| Anti god class frontend | ⚠️ Ajustar | Plano original concentrava tudo em um modal |
| Fork workflow | ❌ Corrigir | `custom/app/javascript/` **não existe** no projeto |
| Design system UI | ⚠️ Ajustar | Referência a `EmailTranscriptModal` é legado; padrão atual é `Dialog` |
| Transport layer | ⚠️ Ajustar | Preferir `prepend_mod_with` + `# FORK:` mínimo vs controller paralelo |
| Reuso pesquisa global | ✅ Bom | `MessageContent`, highlight, debounce — com ressalvas |
| MVP / happy path | ✅ Alinhado | `chatwoot-core.mdc` |
| UX / feedback explícito | ✅ Documentado | [ux-improvements.md](./ux-improvements.md) — 32 itens MVP (UX-M*) |

---

## 1. Architecture.mdc — camadas

### O que o plano acerta

| Regra | Como atender |
|-------|--------------|
| Uma ação de negócio por classe | `Custom::Messages::ConversationSearchService#perform` — busca scoped |
| Transport delega | Controller chama service → JSON |
| Sem HTTP no service | Service só recebe `params` já permitidos |
| Estratégia para variantes | Fase 2: strategy ILIKE / GIN / OpenSearch — não `if` espalhado no controller |

### Desvios a corrigir

#### 1.1 Autorização no service (`authorize_access!`)

O plano original colocava `authorize_access!` dentro do service.

**Problema:** viola a fronteira Transport → Application. `Conversations::BaseController` já faz:

```7:8:app/controllers/api/v1/accounts/conversations/base_controller.rb
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
```

**Correção:** remover autorização duplicada do service. O controller `MessagesController#search` herda `before_action :conversation` — Pundit `show?` é suficiente no MVP.

#### 1.2 Finder vs service monolítico

`MessageFinder` cuida de paginação temporal; `SearchService` mistura vários tipos (aceitável upstream).

**Recomendação fork:** extrair query para finder dedicado:

```
Custom::ConversationMessageSearchFinder  → monta scope ActiveRecord
Custom::Messages::ConversationSearchService → chama finder, pagina, retorna
```

Evita service crescer quando entrarem GIN, transcrição e filtro de `message_type`.

#### 1.3 God class no backend

Risco baixo se o service tiver ~15 linhas e delegar ao finder. Risco alto se copiar `SearchService` inteiro para dentro de um único arquivo.

**Regra:** extrair `MessageSearchStrategy` (LIKE / GIN) só quando a segunda estratégia for implementada — não preemptivamente (`chatwoot-core`).

**Entrega fatiada:** Fase A (content) → Fase C (transcrição) → P1/P2 (GIN/OpenSearch) — ver [implementation-plan.md](./implementation-plan.md).

---

## 2. Fork-workflow.mdc

### Erro crítico: caminho frontend

O plano citava `custom/app/javascript/dashboard/...`.

**Fato:** `config/application.rb` autoloada apenas `custom/app/**` **Ruby**. Não há alias Vite/jsconfig para JS em `custom/`.

**Padrão real do fork:**

| Tipo | Local correto | Exemplo no repo |
|------|---------------|-----------------|
| Service / controller Ruby | `custom/app/...` | `custom/app/services/custom/transcription/orchestrator.rb` |
| Composable | `app/javascript/dashboard/composables/fork/` | `useUnreadCount.js` |
| Componente visual fork | `app/javascript/dashboard/components/fork/` ou feature folder | `UnreadCountBadge.vue`, `ShareContact/` |
| Hook upstream | `# FORK:` mínimo | `ReplyBox.vue`, `routes.rb` |

### Controller: prepend vs arquivo novo

`MessagesController` **não** tem `prepend_mod_with` hoje.

| Abordagem | Merge safety | Recomendação |
|-----------|--------------|--------------|
| `custom/.../messages_controller.rb` duplicado | Ruim | ❌ |
| `# FORK:` método `search` no upstream | Médio | ⚠️ aceitável se 3–5 linhas |
| `MessagesController.prepend_mod_with` + `Custom::MessagesController` | Melhor | ✅ preferido |

```ruby
# custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb
module Custom::Api::V1::Accounts::Conversations::MessagesController
  def search
    @messages = Custom::Messages::ConversationSearchService.new(
      conversation: @conversation,
      params: search_params
    ).perform
  end

  private

  def search_params
    params.permit(:q, :page)
  end
end
```

```ruby
# app/controllers/.../messages_controller.rb (uma linha)
Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with('Api::V1::Accounts::Conversations::MessagesController')
```

Rota continua com `# FORK: collection { get :search }`.

---

## 3. Vue-frontend.mdc e design system

### Desvio: `EmailTranscriptModal` como referência principal

`EmailTranscriptModal.vue` usa **Options API** e padrão antigo.

**Referência correta:** `ShareContactDialog.vue` + `components-next/dialog/Dialog.vue`:

- `<script setup>`
- `defineExpose({ open, close })`
- `width="md"` ou `lg` para lista de resultados
- `overflow-y-auto` no Dialog
- Tailwind only — sem scoped CSS no código novo

Ver [ui-design.md](./ui-design.md).

### Desvio: `SearchInput.vue` completo no modal

`SearchInput` da pesquisa global inclui:
- slot de `SearchFilters` (Enterprise)
- buscas recentes
- atalho `/` global

**Correção:** input dedicado no form com `Input` (`components-next/input/Input.vue`) + debounce no composable — mesmo critério de caracteres (2+), sem acoplar à página `/search`.

### Reuso seguro de upstream

| Componente | Reusar? | Ressalva |
|------------|---------|----------|
| `MessageContent.vue` | ✅ | Tem scoped SCSS upstream — não copiar estilos |
| `SearchResultSection.vue` | ⚠️ | `empty` usa `SEARCH.EMPTY_STATE` com `{item}` — criar chave própria ou passar título fixo |
| `SearchResultMessageItem.vue` | ❌ | `router-link` + metadados de inbox — inadequado in-conversation |

### Anti god class — frontend

**Plano original:** um `ConversationSearchModal.vue` com busca + lista + load more + scroll.

**Estrutura corrigida** (espelha `ShareContact/`):

```
widgets/conversation/ConversationMessageSearch/
├── ConversationMessageSearchDialog.vue   # shell Dialog, open/close
├── ConversationMessageSearchForm.vue     # Input + debounce emit
└── ConversationMessageSearchResultItem.vue  # linha clicável + MessageContent

composables/fork/
├── useConversationMessageSearch.js       # API, estado, paginação
└── useScrollToConversationMessage.js     # merge store + emitter

api/fork/
└── conversationMessageSearch.js          # GET .../messages/search
```

`MoreActions.vue` fica fino: importa dialog, `ref`, `open()` — igual `ReplyBox` → `ShareContactDialog`.

---

## 4. Chatwoot-core.mdc

| Princípio | Avaliação |
|-----------|-----------|
| MVP / happy path | ✅ Busca texto + scroll — sem filtros avançados no MVP |
| Menor diff | ✅ `prepend_mod_with` + pasta feature pequena |
| Sem specs salvo pedido | ✅ Mantido |
| i18n só en + pt_BR no fork | ✅ `conversation.json` |
| Sem docs extras não pedidos | ✅ Esta pasta foi pedida explicitamente |

### i18n — gap

Reutilizar `SEARCH.LOAD_MORE` mistura domínio global com conversa.

**Melhor:** chaves sob `CONVERSATION.MESSAGE_SEARCH.*` com `LOAD_MORE` opcional reexportando a mesma string em en — ou referenciar `SEARCH.LOAD_MORE` conscientemente (DRY vs coesão). Preferência: **namespace próprio** com texto equivalente.

---

## 5. Gaps funcionais não cobertos no plano original

### 5.1 Scroll quando mensagem não está no DOM

`MessagesView#onScrollToMessage` cai em `scrollToBottom()` se elemento não existe — **UX ruim**.

**Melhoria obrigatória no MVP:**
1. Composable carrega janela via `MessageApi.getPreviousMessages`
2. Merge com mutation existente (`SET_PREVIOUS_CONVERSATIONS` ou nova action fork `insertMessagesAroundId`)
3. Só então emitir `SCROLL_TO_MESSAGE`
4. Se ainda falhar → toast/alert com i18n (`CONVERSATION.MESSAGE_SEARCH.MESSAGE_NOT_FOUND`)

### 5.2 `SET_MISSING_MESSAGES` substitui array inteiro

`SET_MISSING_MESSAGES` **replace** `chat.messages = data` — inadequado para inserir janela sem perder mensagens já carregadas.

**Gap:** plano mencionava `mergeMessagesAroundId` sem especificar mutation. Precisa de:
- nova mutation fork que faz merge + sort por `created_at`, ou
- reutilizar padrão de `syncActiveConversationMessages` / `SET_PREVIOUS_CONVERSATIONS`

### 5.3 Highlight via `route.query.messageId`

Funciona (padrão pesquisa global), mas polui URL e pode conflitar com navegação.

**MVP:** aceitável — já usado em `ConversationView`.  
**Melhoria P1:** evento `HIGHLIGHT_MESSAGE` no `emitter` para desacoplar.

### 5.4 Tipos de mensagem e notas privadas

`ConversationFinder#filter_by_query` limita a `incoming` e `outgoing`.

**Decisão MVP a fechar:**
- Incluir `incoming` + `outgoing` + `template` (com content)
- Excluir `activity`
- **Notas privadas:** incluir na busca (agente da conversa); se política exigir, filtrar `private: false` para não-admins — verificar `Message` scopes existentes na implementação

### 5.5 Mensagens deletadas

Conteúdo vira string i18n "deleted" — aparecerão em buscas irrelevantes.

**P2:** excluir `content_attributes->deleted = true`.

### 5.6 Performance

`ILIKE '%term%'` em conversas com dezenas de milhares de mensagens pode ser lento.

**MVP:** aceitável com `conversation_id` index + paginação.  
**P1:** GIN / `search_with_gin` quando flag ativa.  
**P2:** limite máximo de resultados (ex. 100) com mensagem ao usuário.

### 5.7 Command bar

`MoreActions` registra `CMD_MUTE_CONVERSATION`, `CMD_SEND_TRANSCRIPT`.

**Gap:** sem `CMD_SEARCH_IN_CONVERSATION` — power users perdem paridade.

**P2:** registrar emitter + documentar atalho.

### 5.8 Código morto `ConversationView`

`showSearchModal` / `onSearch` — remover na entrega (não conectar ao novo dialog) para evitar dois pontos de entrada divergentes.

### 5.9 Validação de `q` no transport

Controller deve retornar `422` se `q` blank ou &lt; 2 chars — não delegar silêncio ao service (`chatwoot-core`: falhas explícitas).

### 5.10 Constante `PER_PAGE = 15`

Duplica `SearchService`. Aceitável no MVP; **P2** extrair para `Search::DEFAULT_PER_PAGE` se surgir terceiro uso.

---

## 6. Matriz de conformidade por arquivo (plano revisado)

| Arquivo | Camada | God class? | Conforme |
|---------|--------|------------|----------|
| `ConversationMessageSearchFinder` | Application | Não | ✅ |
| `ConversationSearchService` | Application | Não | ✅ |
| `MessagesController` prepend `#search` | Transport | Não | ✅ |
| `conversationMessageSearch.js` | Infrastructure | Não | ✅ |
| `useConversationMessageSearch.js` | Composable | Não | ✅ |
| `useScrollToConversationMessage.js` | Composable | Não | ✅ |
| `ConversationMessageSearchDialog.vue` | Transport/UI | Não | ✅ |
| `ConversationMessageSearchForm.vue` | Transport/UI | Não | ✅ |
| `ConversationMessageSearchResultItem.vue` | Transport/UI | Não | ✅ |
| `MoreActions.vue` (# FORK:) | Transport/UI | Não | ✅ |

---

## 7. Ações no plano (checklist de correção)

- [x] Documentar que **não existe** `custom/app/javascript`
- [x] Trocar referência de modal legado → `Dialog` + `ShareContactDialog` pattern
- [x] Dividir UI em Dialog / Form / ResultItem
- [x] Remover `authorize_access!` do service
- [x] Adicionar `ConversationMessageSearchFinder`
- [x] Preferir `prepend_mod_with` no `MessagesController`
- [x] Especificar mutation/merge de mensagens (não `SET_MISSING_MESSAGES` ingênuo)
- [x] Tratar falha de scroll explicitamente
- [x] Criar [ui-design.md](./ui-design.md)
- [x] Criar [improvements-backlog.md](./improvements-backlog.md)
- [x] Criar [ux-improvements.md](./ux-improvements.md) — catálogo completo UI/UX
- [x] Integrar melhorias UX no MVP ([implementation-plan.md](./implementation-plan.md), P0 UX-M*)
- [x] Confirmar feature **não implementada** no repo
- [x] Documentar fatiamento MVP (Fases A/B/C)
- [x] Documentar mutation fork `INSERT_MESSAGES_AROUND`
- [x] Documentar armadilha camelCase + `MessageContent` para áudio
- [x] Documentar decisões D17–D19 (privadas, deletadas, OpenSearch)
- [x] Implementar código (Fase A)
- [x] Implementar Fase B (scroll robusto)
- [x] Implementar Fase C (polish UX)

---

## 9. Reavaliação pós-investigação no código (jun/2026)

**Data:** jun/2026 · **Escopo:** verificação no repo + alinhamento com rules

### 9.1 Estado real

Feature **implementada** no fork (`custom/` + integração frontend). Atualização jul/2026: guard `MessagesView`, OpenSearch over-fetch, snippet de subject.

| Artefato planejado | Encontrado |
|--------------------|------------|
| `Custom::ConversationMessageSearchFinder` | ✅ |
| `MessagesController#search` + rota | ✅ |
| `ConversationMessageSearch/*` (Vue) | ✅ painel lateral (não Dialog) |
| Item em `MoreActions.vue` + painel lateral | ✅ |
| `INSERT_MESSAGES_AROUND` + poda §8.1 | ✅ |
| Guard `MessagesView#onScrollToMessage` | ✅ — sem `scrollToBottom` se `messageId` ausente |
| `conversationSearch.js` (store) | ✅ — **pesquisa global**, não in-conversation |

### 9.2 Veredito pós-reavaliação

O plano revisado (secções 1–8) permanece **válido e conforme** às rules. Riscos principais na implementação:

| # | Risco | Mitigação documentada |
|---|-------|----------------------|
| R1 | `MessagesView#onScrollToMessage` faz `scrollToBottom()` se elemento não existe | ✅ Guard FORK: só `scrollToBottom` sem `messageId`; busca emite toast |
| R2 | `SET_MISSING_MESSAGES` **replace** o array; `SET_PREVIOUS_CONVERSATIONS` só `unshift` | Nova mutation `INSERT_MESSAGES_AROUND` — ver [implementation-plan.md](./implementation-plan.md) §2.2 |
| R3 | `MessageContent.vue` usa `file_type` / `transcribed_text` (snake); API com `useCamelCase` não exibe áudio | ResultItem espelha `SearchResultMessageItem` + `readTranscriptText` |
| R4 | Escopo UX (19 P0 + 32 UX-M) vs `chatwoot-core` MVP | Fases A/B/C — não entregar tudo de uma vez |
| R5 | Contas Enterprise com OpenSearch: in-conversation ILIKE &lt; global OpenSearch | Documentado D19; P2.1 backlog |

### 9.3 Path do prepend controller

Seguir padrão Enterprise (não confundir com controllers standalone em `custom/app/controllers/api/`):

| Peça | Path |
|------|------|
| Módulo prepend | `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` |
| Hook upstream | `Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with(...)` |

---

## 8. Referências internas do fork a seguir

| Feature | O que copiar |
|---------|--------------|
| [share-contact-card/ui-design.md](../share-contact-card/ui-design.md) | Dialog, Tailwind, estrutura de pastas |
| [conversation-unread-badge](../conversation-unread-badge-on-contact-avatar/implementation-plan.md) | `composables/fork` + `components/fork` |
| [ux-improvements.md](./ux-improvements.md) | Catálogo UX MVP + roadmap P1–P3 |
| Pesquisa global | `MessageContent`, debounce 500ms, paginação 15 |
| `api-endpoints.md` | Matriz de rotas — 1 endpoint novo |
| `ShareContactDialog` | `defineExpose({ open, close })` acionado pelo pai |
