# Estado atual — Pesquisa global vs. pesquisa in-conversation

## Contexto do pedido

O usuário quer uma opção de pesquisa **dentro da conversa aberta**, no menu de ações do header (captura: "Bloquear contato", "Enviar transcrição"). O objetivo é localizar mensagens no histórico daquela conversa e saltar para o trecho encontrado.

---

## 1. Menu de ações da conversa (ponto de entrada)

**Arquivo:** `app/javascript/dashboard/components/widgets/conversation/MoreActions.vue`

Montado em `ConversationHeader.vue`:

```176:176:app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue
      <MoreActions :conversation-id="currentChat.id" />
```

Itens atuais do dropdown:

| Ação | Ícone | Comportamento |
|------|-------|---------------|
| Bloquear / Desbloquear contato | `volume-off` / `volume-1` | `muteConversation` / `unmuteConversation` |
| Enviar transcrição | `share` | Abre `EmailTranscriptModal` |

Padrão estabelecido:
- Item no `actionMenuItems` → `handleActionClick` → modal ou dispatch Vuex
- Command bar via `emitter` (`CMD_MUTE_CONVERSATION`, `CMD_SEND_TRANSCRIPT`)

**Gap:** não há item "Pesquisar nesta conversa".

---

## 2. Pesquisa global existente (`/search`)

### Frontend

| Peça | Caminho | Função |
|------|---------|--------|
| Página | `modules/search/components/SearchView.vue` | Orquestra busca, abas, filtros |
| Input | `modules/search/components/SearchInput.vue` | Debounce, atalho `/`, buscas recentes |
| Filtros | `modules/search/components/SearchFilters.vue` | Horário, remetente, inbox (só mensagens) |
| Resultados mensagem | `SearchResultMessagesList.vue` + `SearchResultMessageItem.vue` + `MessageContent.vue` | Lista com highlight |
| Store | `store/modules/conversationSearch.js` | `fullSearch`, `messageSearch`, paginação |
| API | `api/search.js` | `GET /api/v1/accounts/:id/search/messages` |

### Backend

| Peça | Caminho | Função |
|------|---------|--------|
| Controller | `app/controllers/api/v1/accounts/search_controller.rb` | Delega para `SearchService` |
| Service | `app/services/search_service.rb` | `filter_messages` (LIKE / GIN / OpenSearch Enterprise) |
| Enterprise | `enterprise/app/services/enterprise/search_service.rb` | OpenSearch com filtros |

### Comportamento relevante para reutilização

**Mensagens — o que pesquisa:**
- `messages.content` (ILIKE ou GIN `@@ to_tsquery`)
- Enterprise: também `attachments.transcribed_text`, assunto de e-mail

**Mensagens — filtros (feature `advanced_search`):**
- Horário (`since` / `until`)
- Remetente (`from=contact:N` ou `agent:N`)
- Inbox (`inbox_id`)

**Mensagens — limitações:**
- Base query SQL: `created_at >= 3.months.ago` em `message_base_query`
- **Não existe** parâmetro `conversation_id` hoje
- Paginação: 15 por página

**Conversas na pesquisa global:**
- Pesquisa por `display_id` + dados do contato — **não** por conteúdo de mensagem
- Filtros de inbox/remetente **não** se aplicam a conversas (só mensagens)

### Navegação resultado → conversa

`SearchResultMessageItem` gera URL com `messageId` na query:

```48:56:app/javascript/dashboard/modules/search/components/SearchResultMessageItem.vue
const navigateTo = computed(() => {
  const params = {};
  if (props.messageId) {
    params.messageId = props.messageId;
  }
  return frontendURL(
    `accounts/${props.accountId}/conversations/${props.id}`,
    params
  );
});
```

`ConversationView` lê `messageId` e emite scroll:

```174:181:app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
```

`Message.vue` aplica highlight temporário quando `route.query.messageId` coincide.

---

## 3. API de mensagens da conversa (carregamento paginado)

**Controller:** `Api::V1::Accounts::Conversations::MessagesController#index`  
**Finder:** `MessageFinder` — paginação por `before` / `after`, **sem** parâmetro `q`

| Modo | Limite | Uso |
|------|--------|-----|
| `messages_latest` | 20 mensagens | Carga inicial |
| `messages_before` | 20 | Scroll para cima |
| `messages_after` | 100 | Sincronização |
| `messages_between` | 1000 | Intervalo explícito |

**Gap:** não há endpoint de busca textual scoped à conversa.

---

## 4. Scroll para mensagem (mecanismo existente)

**Evento:** `BUS_EVENTS.SCROLL_TO_MESSAGE`  
**Listener:** `MessagesView.vue#onScrollToMessage`

```329:340:app/javascript/dashboard/components/widgets/conversation/MessagesView.vue
    onScrollToMessage({ messageId = '' } = {}) {
      this.$nextTick(() => {
        const messageElement = document.getElementById('message' + messageId);
        if (messageElement) {
          this.isProgrammaticScroll = true;
          messageElement.scrollIntoView({ behavior: 'smooth' });
          this.fetchPreviousMessages();
        } else {
          this.scrollToBottom();
        }
      });
      this.makeMessagesRead();
    },
```

**Limitação:** se a mensagem não está no DOM (não carregada no store), o scroll falha silenciosamente (vai para o final).

**Padrão de carga sob demanda:** `MessageList.vue#fetchReplyMessage` usa `MessageApi.getPreviousMessages` com janela `before: messageId + 100, after: messageId - 100` para trazer mensagens ao redor de um ID.

---

## 5. Código morto / intenção não finalizada

`ConversationView.vue` já declara estado e métodos para modal de busca, **sem uso no template**:

```66:69:app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue
  data() {
    return {
      showSearchModal: false,
    };
```

```187:192:app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
```

Indica que busca in-conversation foi considerada upstream, mas nunca conectada ao menu nem a um componente.

---

## 6. Filtro de lista de conversas (não confundir)

`ConversationFinder#filter_by_query` filtra a **lista lateral** de conversas quando `params[:q]` está presente — join em `messages.content`. Isso é diferente de buscar dentro de uma conversa já aberta.

---

## 7. Componentes reutilizáveis (inventário)

| Componente / util | Reutilizar? | Observação |
|-------------------|-------------|------------|
| `MessageContent.vue` | ✅ Sim | Highlight com `useMessageFormatter#highlightContent` |
| `SearchInput.vue` | ✅ Parcial | Debounce e UX; sem filtros avançados no modal |
| `SearchResultMessageItem.vue` | ⚠️ Adaptar | Hoje é `router-link`; in-conversation precisa `@click` → scroll |
| `SearchResultSection.vue` | ✅ Sim | Título, empty state, loading |
| `ShareContactDialog.vue` + `Dialog.vue` | ✅ Referência | Padrão modal moderno (`defineExpose`, Composition API) |
| `EmailTranscriptModal.vue` | ⚠️ Legado | Options API — não usar como base de design |
| `SearchAPI.messages` | ⚠️ Estender | Precisa `conversation_id` ou endpoint dedicado |
| `conversationSearch` store | ❌ Não | Acoplado à pesquisa global multi-entidade |
| `BUS_EVENTS.SCROLL_TO_MESSAGE` | ✅ Sim | Navegação in-place |
| `Message.vue` highlight | ✅ Sim | Pode usar query ou prop/event dedicado |

---

## 8. Gaps principais

1. **Sem endpoint** de busca textual por `conversation_id`
2. **Sem item de menu** em `MoreActions`
3. **Sem modal/painel** de busca in-conversation
4. **Scroll falha** se mensagem antiga não estiver carregada — precisa fluxo "carregar janela + scroll" (como `fetchReplyMessage`)
5. **Limite de 3 meses** na `SearchService` impede histórico completo se reutilizarmos o endpoint global sem ajuste
6. **Código morto** em `ConversationView` — remover na entrega
7. **UX** — plano em [ux-improvements.md](./ux-improvements.md)
8. **Transcrição de áudio** — texto em `attachments.meta`; pesquisa global SQL não cobre; in-conversation MVP **sim** — ver [audio-transcription-search.md](./audio-transcription-search.md)

---

## 9. Transcrição de áudio e pesquisa (resumo)

| Aspeto | Detalhe |
|--------|---------|
| Armazenamento | `attachments.meta` — chaves `transcribed_text` e `transcription.text` |
| Fork Groq | Manual (orelha); `Custom::Transcription::Orchestrator` |
| Enterprise OpenAI | Desativado auto no fork; mesmo writer `TranscriptionMetadata` |
| Pesquisa global ILIKE | **Não** busca transcrição |
| Pesquisa global OpenSearch | Busca `attachments.transcribed_text` |
| UI global | `MessageContent` + `TranscribedText` já exibem |
| Plano in-conversation | Finder com `left_joins(:attachments)` + OR em meta JSON |

---

## 9. Feature flags envolvidas

| Flag | Impacto na busca in-conversation |
|------|----------------------------------|
| `advanced_search` | Filtros horário/remetente/inbox na pesquisa global — **fora do escopo MVP** |
| `search_with_gin` | GIN index em `messages.content` — útil se reutilizarmos lógica SQL do `SearchService` |
| OpenSearch (`ChatwootApp.advanced_search_allowed?`) | Enterprise — opcional na Fase 2+ |

**Recomendação MVP:** não exigir `advanced_search` para busca in-conversation — é funcionalidade básica de produtividade do agente.
