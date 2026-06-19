# Plano de implementação — Pesquisa de mensagens na conversa (revisado)

Plano alinhado a [rules-compliance-review.md](./rules-compliance-review.md), [ui-design.md](./ui-design.md), [ux-improvements.md](./ux-improvements.md) e [audio-transcription-search.md](./audio-transcription-search.md).

**Pré-requisitos:** [current-state.md](./current-state.md) · [implementation-decision-tree.md](./implementation-decision-tree.md)

---

## Objetivo

1. Agente abre menu ⋮ → **"Pesquisar nesta conversa"**
2. `Dialog` com busca em **texto da mensagem e transcrições de áudio**
3. Clique no resultado: scroll + highlight 1s (com loading na thread se necessário)
4. Paginação 15/página; fork merge-safe; i18n en + pt_BR

---

## Escopo MVP

### In scope — técnico

- `GET .../conversations/:id/messages/search?q=&page=`
- `Custom::ConversationMessageSearchFinder` — **query unificada** (ver secção Fase 1)
- `Custom::Messages::ConversationSearchService` + `includes(:attachments, :sender)`
- `MessagesController.prepend_mod_with` + rota `# FORK:`
- Pesquisa em:
  - `messages.content` (incoming, outgoing, template)
  - `attachments.meta` — `transcribed_text` e `transcription.text` (só `file_type: audio`)
- Merge scroll (`INSERT_MESSAGES_AROUND`)
- Limpeza `ConversationView` código morto

### In scope — UI/UX

- Todos os itens UX-M* em [ux-improvements.md](./ux-improvements.md)
- **UX-M33:** badge `i-lucide-mic` quando resultado é match em transcrição
- Snippet via `MessageContent` + `TranscribedText` para áudio (padrão pesquisa global)

### Out of scope (MVP)

- Assunto e-mail, GIN, OpenSearch
- `matched_on` explícito na API (inferir no FE — ver [audio-transcription-search.md](./audio-transcription-search.md) §4.4)
- Alinhar `SearchService` global SQL (P1 opcional)
- ⌘F, filtros remetente, specs

---

## Arquitetura

```
GET .../messages/search?q=
  └── MessagesController#search
        └── ConversationSearchService#perform
              └── ConversationMessageSearchFinder#perform
                    ├── messages.content ILIKE
                    └── attachments.meta (audio) ILIKE  ← transcrição Groq/OpenAI

JSON message + attachments.transcribed_text
  └── ConversationMessageSearchResultItem
        ├── MessageContent (highlight)
        └── mic badge se match transcrição
```

---

## Fase 1 — Backend

### 1.1 Finder (query unificada)

**Arquivo:** `custom/app/finders/custom/conversation_message_search_finder.rb`

Responsabilidade única: montar scope com texto **e** transcrição.

```ruby
module Custom
  class ConversationMessageSearchFinder
    SEARCHABLE_TYPES = %w[incoming outgoing template].freeze
    AUDIO_FILE_TYPE = Attachment.file_types[:audio].freeze

    pattr_initialize [:conversation!, :query!]

    def perform
      return Message.none if sanitized_query.blank?

      pattern = "%#{sanitized_query}%"

      conversation.messages
                  .left_joins(:attachments)
                  .where(message_type: SEARCHABLE_TYPES)
                  .where(search_predicate, pattern: pattern, audio_type: AUDIO_FILE_TYPE)
                  .distinct
                  .reorder('messages.created_at DESC')
    end

    private

    def sanitized_query
      query.to_s.strip.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end

    def search_predicate
      <<~SQL.squish
        messages.content ILIKE :pattern
        OR (
          attachments.file_type = :audio_type
          AND attachments.meta->>'transcribed_text' ILIKE :pattern
        )
        OR (
          attachments.file_type = :audio_type
          AND attachments.meta->'transcription'->>'text' ILIKE :pattern
        )
      SQL
    end
  end
end
```

**Alinhamento com transcrição fork:**

| Origem | Chave em `meta` | Coberta |
|--------|-----------------|---------|
| Groq manual | `transcription.text` + `transcribed_text` | ✅ |
| OpenAI Enterprise | idem via `TranscriptionMetadata.write_transcription` | ✅ |
| Áudio sem transcrição | `meta` vazio | Excluído (OR falso) |
| `state: processing` sem text | sem texto | Excluído |

Detalhes: [audio-transcription-search.md](./audio-transcription-search.md).

### 1.2 Service

**Arquivo:** `custom/app/services/custom/messages/conversation_search_service.rb`

```ruby
def perform
  return Message.none if query.blank?

  Custom::ConversationMessageSearchFinder
    .new(conversation: conversation, query: query)
    .perform
    .includes(:attachments, :sender)
    .page(page)
    .per(PER_PAGE)
end
```

### 1.3 Controller prepend

- `invalid_query?` → 422
- `params.permit(:q, :page)`
- View: partial `_message.json.jbuilder` (attachments com `transcribed_text`)

### 1.4 Rota

```ruby
# FORK: in-conversation message search
collection { get :search }
```

---

## Fase 2 — Frontend infra

### 2.1 `useConversationMessageSearch.js`

- Debounce 500ms; mínimo 2 caracteres
- `useCamelCase` nos resultados (attachments: `transcribedText`, `fileType`)
- Helper `isTranscriptionMatch(message, query)`:

```javascript
import { readTranscriptText } from 'dashboard/composables/fork/useTranscriptText';

export const isTranscriptionMatch = (message, query) => {
  if (message.content?.trim()) return false;
  const audio = message.attachments?.find(a => a.fileType === 'audio');
  const text = readTranscriptText(audio);
  return text.toLowerCase().includes(query.toLowerCase());
};
```

### 2.2 `useScrollToConversationMessage.js`

Sem alteração — salta para `message.id` independente do match ser content ou transcrição.

---

## Fase 3 — UI

### ConversationMessageSearchResultItem.vue

```vue
<MessageContent :message="message" :search-term="query" :author="authorName" />

<div v-if="isTranscriptionMatch(message, query)" class="flex items-center gap-1.5 mt-1 text-n-slate-11">
  <Icon icon="i-lucide-mic" class="size-3.5" />
  <span class="text-xs">{{ t('CONVERSATION.MESSAGE_SEARCH.MATCH_TRANSCRIPTION') }}</span>
</div>
```

Reutilizar `TranscribedText` quando quiser label "Transcrição" explícita (como `SearchResultMessageItem` global).

### Demais componentes

Ver [ui-design.md](./ui-design.md) e [ux-improvements.md](./ux-improvements.md).

---

## Fase 4 — i18n

Chaves adicionais:

```json
"MATCH_TRANSCRIPTION": "Match in audio transcription",
"HINT_AUDIO": "Search includes transcribed audio messages"
```

`en` + `pt_BR` em `conversation.json`.

---

## Matriz de reutilização

| Peça | Reuso na pesquisa + áudio |
|------|---------------------------|
| `TranscriptionMetadata.read_text` | Lógica espelhada no SQL do finder |
| `MessageContent.vue` | Snippet + highlight transcrição |
| `useTranscriptText.js` | Deteção match transcrição no FE |
| `TranscribedText.vue` | Label opcional nos resultados |
| `SearchResultMessageItem.vue` | Referência visual para áudio |

---

## Critérios de aceite

### Pesquisa unificada (texto + áudio)

- [ ] Termo só em `messages.content` → resultado com highlight no texto
- [ ] Termo só em transcrição Groq → resultado com snippet da transcrição + badge mic
- [ ] Áudio sem transcrição → não aparece
- [ ] `distinct` — mensagem não duplicada com múltiplos attachments
- [ ] Transcrição OpenAI legada (se existir) → mesmo comportamento

### Técnico + UX geral

- [ ] Ver checklist completo em [ux-improvements.md](./ux-improvements.md)
- [ ] `includes(:attachments)` — sem N+1
- [ ] Escape wildcards ILIKE na query

---

## Ordem de entrega

| # | Entrega |
|---|---------|
| 1 | Finder unificado + service + controller + rota |
| 2 | API/composable + `isTranscriptionMatch` |
| 3 | Dialog + ResultItem com mic badge |
| 4 | Scroll merge + i18n |
| 5 | Testes manuais áudio (secção 7 de audio-transcription-search.md) |

---

## Test plan — áudio transcrito

1. Transcrever áudio manualmente (orelha) com termo único
2. Pesquisar termo → aparece com badge mic
3. Pesquisar termo que só existe noutra mensagem texto → não mistura
4. Áudio não transcrito → não aparece para nenhum termo do áudio
5. Clique no resultado áudio → scroll + highlight na bolha correta
