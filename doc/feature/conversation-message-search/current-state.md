# Estado atual — Pesquisa global vs. pesquisa in-conversation

> Documento de apoio. Decisões normativas e ordem de execução estão no [plano consolidado](./implementation-plan.md).

> **Atualização jun/2026:** a feature in-conversation **está implementada** no fork (`custom/` + integração frontend). Este doc descreve o que existe no código hoje e o que ainda difere da pesquisa global.

## Contexto

O agente pode pesquisar mensagens **dentro da conversa aberta** — texto, assunto de e-mail e transcrições de áudio — e saltar para o resultado no histórico.

---

## 1. Entrada UI (implementado)

| Entrada | Arquivo |
|---------|---------|
| Menu ⋮ "Pesquisar nesta conversa" | `MoreActions.vue` |
| Botão lateral (lupa) | `SidepanelSwitch.vue` |
| ⌘F / Ctrl+F (exceto em inputs) | `MoreActions.vue` |
| Command bar | `CMD_SEARCH_IN_CONVERSATION` |

Painel: `ConversationMessageSearchPanel.vue` + `ConversationMessageSearchView.vue`

---

## 2. Backend (implementado)

| Peça | Caminho |
|------|---------|
| Rota | `GET .../conversations/:id/messages/search` (`config/routes.rb`) |
| Controller | `custom/.../messages_controller.rb` (`prepend_mod_with`) |
| Finder | `Custom::ConversationMessageSearchFinder` |
| SQL helpers | `custom/lib/custom/message_search/*` |
| View JSON | `app/views/.../messages/search.json.jbuilder` |

**Motores de busca:** ILIKE → GIN (com `search_with_gin`) → unaccent → OpenSearch (`advanced_search`), com fallback SQL.

**Escopo:** `incoming`, `outgoing`, `template`; exclui `activity` e mensagens com `content_attributes.deleted`.

---

## 3. Frontend (implementado)

| Peça | Caminho |
|------|---------|
| Composable busca | `useConversationMessageSearch.js` |
| Composable painel | `useConversationMessageSearchPanel.js` |
| Scroll para mensagem | `useScrollToConversationMessage.js` |
| Erros i18n | `resolveConversationMessageSearchError.js` |
| API client | `conversationMessageSearch.js` |
| Store merge | `INSERT_MESSAGES_AROUND` mutation |

**UX:** debounce 500ms, `AbortController`, filtros (todas/cliente/agente/privadas), buscas recentes (`sessionStorage`), infinite scroll, erros PT-BR/en/pt.

---

## 4. Pesquisa global (`/search`) — separada

O store `conversationSearch.js` e `SearchService` servem a **pesquisa global** multi-conta. Não confundir com in-conversation.

A pesquisa global SQL **não** busca transcrição de áudio; in-conversation **sim**.

---

## 5. Scroll para mensagem antiga (implementado)

Fluxo ao clicar num resultado:

1. Injeta mensagem no store (`INSERT_MESSAGES_AROUND`)
2. Se não estiver no DOM, busca janela via `MessageApi.getPreviousMessages`
3. Emite `SCROLL_TO_MESSAGE` + highlight temporário

---

## 6. Gaps remanescentes (pós-implementação)

| Item | Prioridade | Notas |
|------|------------|-------|
| Reindex OpenSearch após campo `deleted` | P2 | `rake conversation_message_search:reindex_hints` |
| Erros API do controller em inglês | P3 | Frontend mapeia 422 principais |
| Specs OpenSearch reais (sem stub) | P3 | Requer cluster em CI |
| Excluir `deleted` do índice na origem (skip callback) | P3 | Filtro `where` já resolve páginas curtas |

**Resolvido nesta rodada:** OpenSearch `deleted` na query; `MessagesView` sem fallback `scrollToBottom`; poda Vuex §8.1; GIN global com assunto de e-mail.

---

## 7. Testes

| Suite | Cobertura |
|-------|-----------|
| `spec/custom/.../messages_search_spec.rb` | API |
| `spec/custom/finders/..._finder_spec.rb` | Finder SQL + OpenSearch stub + `transcribed_text` legado |
| `spec/presenters/messages/search_data_presenter_spec.rb` | `deleted`, transcrição Groq |
| `spec/custom/lib/custom/message_search/` | `ContentAttributes`, `Tsquery` |
| Vitest `composables/fork/spec/` | Erros, painel, busca, scroll, mutations poda |

Comandos: `rake conversation_message_search:acceptance` · `rake conversation_message_search:smoke[...]` · `rake conversation_message_search:reindex_hints`

---

## 8. Feature flags

| Flag | Impacto |
|------|---------|
| `search_with_gin` | GIN tsquery no content + ILIKE em subject/transcrição |
| `advanced_search` | OpenSearch via Searchkick |
| Extensão `unaccent` | ILIKE accent-insensitive (`db/migrate/20260619120000`) |

In-conversation **não** exige `advanced_search` — funciona com ILIKE por defeito.
