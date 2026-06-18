# Conversation Unread Badge on Contact Avatar (Chatwoot Fork)

## Context

Exibir o total de mensagens não lidas como badge sobre o avatar do contato nos cards de conversa, de forma consistente entre layouts.

Antes da implementação, o contador aparecia em locais diferentes (coluna direita no card legado, preview/meta no components-next). Agora o indicador visual único fica sobre o avatar do contato quando há thumbnail.

## Objective

1. Exibir badge sobre avatar quando `unread_count > 0`
2. Ocultar badge quando `unread_count = 0`
3. Exibir `9+` para valores acima de 9
4. Evitar duplicidade de contador no mesmo card
5. Manter comportamento atual de hover/seleção/checkbox
6. Fallback compacto quando o avatar está oculto (`hideThumbnail`)

## Scope

### In Scope

- Lista principal condensada (`widgets/conversation/ConversationCard.vue`)
- Lista principal expanded (`ConversationCardExpanded.vue`)
- Histórico de contato/empresa (`components-next/Conversation/ConversationCard/ConversationCard.vue`)
- Componentes e composables fork para integração merge-safe

### Out of Scope

- Alterar cálculo de unread no backend
- Mudar APIs de conversas
- Feature flag global
- Rework completo de layout dos cards
- Badge na sidebar (`SidebarUnreadBadge` mantém cap `99+` — contexto distinto)

### Fora do escopo com fallback

| View | Comportamento |
|------|---------------|
| `ContactConversations.vue` | Usa card legado com `hide-thumbnail` — badge aparece na coluna de timestamp (fallback compacto), não no avatar |

## As-Built Architecture

```
normalizeUnreadCount.js (helper fork)
  └── normalizeUnreadCount(raw) → integer ≥ 0
  └── formatConversationUnreadBadgeLabel(count) → "9+" cap
  └── CONVERSATION_UNREAD_BADGE_CAP = 9

useUnreadCount (composable fork)
  └── lê unreadCount / unread_count → normalizeUnreadCount

UnreadCountBadge (componente visual fork)
  └── render + label 9+; espera count já normalizado

ConversationCardForkAvatarBadge (wrapper fork)
  └── posicionamento absolute sobre avatar

Cards consumidores:
  ├── ConversationCard.vue (legado) via useUnreadCount + fork badge
  ├── ConversationCardExpanded.vue via useUnreadCount + fork badge
  └── ConversationCard.vue (components-next histórico) via useUnreadCount + fork badge
```

### Arquivos principais

| Arquivo | Responsabilidade |
|---------|------------------|
| `composables/fork/normalizeUnreadCount.js` | Normalização única + cap `9+` para cards |
| `composables/fork/useUnreadCount.js` | Lê payload da conversa e expõe `unreadCount` / `hasUnread` |
| `components/fork/UnreadCountBadge.vue` | Badge visual puro (sem store, sem i18n) |
| `components/fork/ConversationCardForkAvatarBadge.vue` | Posicionamento absolute sobre avatar |
| `composables/fork/useConversationCardFork.js` | Apenas assignme — **sem** lógica de unread |
| `components/fork/specs/UnreadCountBadge.spec.js` | Testes de render do badge |
| `composables/fork/spec/normalizeUnreadCount.spec.js` | Testes de normalização e label |
| `composables/fork/spec/useUnreadCount.spec.js` | Testes do composable |

### Integração por layout

| Layout | Arquivo | Badge no avatar | Fallback sem avatar | Contador duplicado removido |
|--------|---------|-----------------|---------------------|----------------------------|
| Lista condensada | `widgets/conversation/ConversationCard.vue` | ✅ `ConversationCardForkAvatarBadge` | ✅ `UnreadCountBadge` junto ao `TimeAgo` quando `hideThumbnail` | ✅ |
| Lista expanded | `ConversationCardExpanded.vue` | ✅ fork badge | — | ✅ (só estilo em `CardContent`) |
| Histórico contato/empresa | `components-next/.../ConversationCard.vue` | ✅ fork badge | — | ✅ |
| Painel contato (`ContactConversations`) | card legado + `hide-thumbnail` | — | ✅ badge no timestamp | ✅ |

## Project Rules Applied

- Overlay fork em `components/fork/` e `composables/fork/` — sem arquivos novos em `components-next/`
- Marcadores `// FORK:` / `<!-- FORK: -->` nos pontos de integração
- `useConversationCardFork` restrito ao assignme (SRP)
- `ConversationItem` faz `provide('conversationCardAssignmeFork')` para evitar double-call no card legado
- Tailwind only (sem CSS custom novo)
- MVP, happy path primeiro
- Normalização centralizada em `normalizeUnreadCount.js` (sem duplicar em badge + composable)

## UX and Visual Behavior

- Badge no canto **superior esquerdo** do avatar (`-top-1 ltr:-left-1 rtl:-right-1`)
- Offset negativo para sobrepor borda do avatar sem cobrir o centro
- `bg-n-brand`, `text-xxs`, `shadow-lg`, compatível com avatares 24px e 40px
- Limite visual nos **cards de conversa**: **`9+`** (`CONVERSATION_UNREAD_BADGE_CAP`)
- Sidebar mantém **`99+`** (`SidebarUnreadBadge`) — densidade e escala diferentes
- `pointer-events-none` para não bloquear clique/hover/checkbox
- Com `hideThumbnail`: badge inline acima do timestamp (ex.: `ContactConversations`)

## Data and Contracts

Sem mudanças de backend. Campos consumidos:

- legado/expanded: `chat.unread_count`
- components-next: `conversation.unreadCount` (preferido; fallback `unread_count`)

Normalização em `normalizeUnreadCount`: `null`, `undefined`, string não numérica, negativo → `0`; frações → `Math.floor`.

## Reliability

- Normalização única em `normalizeUnreadCount.js`
- `UnreadCountBadge` confia em count pré-normalizado do composable
- Testes: normalização (`0`, `1`, `9`, `10`, `null`, `undefined`, `-1`, `'3'`, `3.7`) + render do badge
- Atualização reativa via props/store existentes (sem watchers extras)

## Decisions (closed)

| Questão | Decisão |
|---------|---------|
| Posição no avatar | Superior esquerdo (offset negativo) |
| Limite visual nos cards | `9+` via `CONVERSATION_UNREAD_BADGE_CAP` |
| Limite na sidebar | `99+` — componente separado, fora deste escopo |
| Contador na coluna direita | Removido — badge único por card |
| Sem avatar (`hideThumbnail`) | Badge compacto junto ao timestamp |
| Estratégia fork | `components/fork/` + `composables/fork/`, edits mínimos upstream com `FORK:` |
| assignme vs unread | Composables separados (`useConversationCardFork` / `useUnreadCount`) |

## Acceptance Criteria

- [x] Badge sobre avatar em todos os layouts do escopo com thumbnail
- [x] Fallback compacto quando avatar oculto
- [x] Sem badge quando unread = 0
- [x] Exibição `9+` para contagens altas nos cards
- [x] Sem duplicidade de contador no mesmo card
- [x] Sem regressão de clique/hover/seleção
- [x] Fallback seguro para valores inválidos
- [x] Testes passando
- [x] Arquivos fork fora de `components-next/`

## Manual Test Plan

1. Lista condensada: unread 0 / 1–9 / 10+ → badge correto ou ausente
2. Lista expanded (wide + setting): mesmo comportamento no avatar do contato
3. Histórico de contato (sidebar): badge no avatar, preview/nome com estilo unread
4. Painel contato (`hideThumbnail`): badge na coluna direita, sem avatar
5. Checkbox/overlay no avatar legado: interação intacta
6. Mark-as-read/unread em tempo real: badge atualiza
7. Tema light/dark

## Rollout

Entrega direta (sem feature flag). Rollback por revert frontend.
