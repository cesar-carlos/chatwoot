# Conversation Unread Badge on Contact Avatar (Chatwoot Fork)

## Context

Exibir o total de mensagens não lidas como badge sobre o avatar do contato nos cards de conversa, de forma consistente entre layouts.

Antes da implementação, o contador aparecia em locais diferentes (coluna direita no card legado, preview/meta no components-next). Agora o indicador visual único fica sobre o avatar do contato.

## Objective

1. Exibir badge sobre avatar quando `unread_count > 0`
2. Ocultar badge quando `unread_count = 0`
3. Exibir `9+` para valores acima de 9
4. Evitar duplicidade de contador no mesmo card
5. Manter comportamento atual de hover/seleção/checkbox

## Scope

### In Scope

- Lista principal condensada (`widgets/conversation/ConversationCard.vue`)
- Lista principal expanded (`ConversationCardExpanded.vue`)
- Histórico de contato/empresa (`components-next/Conversation/ConversationCard/ConversationCard.vue`)
- Componente visual reutilizável + overlay fork para merge-safe integration

### Out of Scope

- Alterar cálculo de unread no backend
- Mudar APIs de conversas
- Feature flag global
- Rework completo de layout dos cards

## As-Built Architecture

```
useUnreadCount (composable fork)
  └── normaliza unreadCount / unread_count → number seguro

UnreadCountBadge (componente visual puro)
  └── safeCount, label 9+, pointer-events-none

ConversationCardForkAvatarBadge (wrapper fork)
  └── posicionamento absolute + integração merge-safe

Cards consumidores:
  ├── ConversationCard.vue (legado condensado) via useConversationCardFork
  ├── ConversationCardExpanded.vue via useUnreadCount
  └── ConversationCard.vue (components-next histórico) via useUnreadCount
```

### Arquivos principais

| Arquivo | Responsabilidade |
|---------|------------------|
| `UnreadCountBadge.vue` | Badge visual fail-safe (sem store, sem i18n) |
| `ConversationCardForkAvatarBadge.vue` | Posicionamento sobre avatar; evita edits upstream |
| `useUnreadCount.js` | Normalização centralizada de count |
| `useConversationCardFork.js` | Integração fork no card legado (unread + assignme) |
| `UnreadCountBadge.spec.js` | Testes de normalização e render |

### Integração por layout

| Layout | Arquivo | Badge no avatar | Contador duplicado removido |
|--------|---------|-----------------|-----------------------------|
| Lista condensada | `widgets/conversation/ConversationCard.vue` | ✅ via `ConversationCardForkAvatarBadge` | ✅ removido `UnreadBadge` da coluna direita |
| Lista expanded | `ConversationCardExpanded.vue` | ✅ wrapper `relative` + fork badge | ✅ removido de `CardContent.vue` |
| Histórico contato | `components-next/.../ConversationCard.vue` | ✅ via fork badge | ✅ removido de previews |

## Project Rules Applied

- Overlay fork em `custom/` (`ConversationCardForkAvatarBadge`, `useUnreadCount`) para minimizar conflitos upstream
- Marcadores `// FORK:` nos pontos de integração upstream inevitáveis
- Tailwind only (sem CSS custom novo)
- MVP, happy path primeiro
- Componente visual puro sem lógica de negócio (SOLID: uma responsabilidade)

## UX and Visual Behavior

- Badge no canto **superior esquerdo** do avatar (`-top-1 ltr:-left-1 rtl:-right-1`)
- Offset negativo para sobrepor borda do avatar sem cobrir o centro
- `bg-n-brand`, `text-xxs`, `shadow-lg`, compatível com avatares 24px e 40px
- Limite visual: **`9+`** (hardcoded no componente, sem i18n)
- `pointer-events-none` para não bloquear clique/hover/checkbox

## Data and Contracts

Sem mudanças de backend. Campos consumidos:

- legado/expanded: `chat.unread_count`
- components-next: `conversation.unreadCount` (fallback para `unread_count`)

Normalização em `useUnreadCount`: `null`, `undefined`, string não numérica, negativo → `0`.

## Reliability

- `UnreadCountBadge.vue`: `safeCount` com `Number()` + clamp ≥ 0
- Testes: `0`, `1`, `9`, `10`, `null`, `undefined`, `-1`, `'3'`
- Atualização reativa via props/store existentes (sem watchers extras)

## Decisions (closed)

| Questão | Decisão |
|---------|---------|
| Posição no avatar | Superior esquerdo (offset negativo) |
| Limite visual | `9+` |
| Contador na coluna direita | Removido — badge único no avatar |
| Estratégia fork | Wrapper + composable em `custom/`, não edit direto em upstream quando possível |

## Acceptance Criteria

- [x] Badge sobre avatar em todos os layouts do escopo
- [x] Sem badge quando unread = 0
- [x] Exibição `9+` para contagens altas
- [x] Sem duplicidade de contador no mesmo card
- [x] Sem regressão de clique/hover/seleção
- [x] Fallback seguro para valores inválidos
- [x] Testes de componente passando
- [x] Lint sem novos erros nos arquivos alterados

## Manual Test Plan

1. Lista condensada: unread 0 / 1–9 / 10+ → badge correto ou ausente
2. Lista expanded (wide + setting): mesmo comportamento no avatar do contato
3. Histórico de contato (sidebar): badge no avatar, sem badge no preview
4. Checkbox/overlay no avatar legado: interação intacta
5. Mark-as-read/unread em tempo real: badge atualiza
6. Tema light/dark

## Rollout

Entrega direta (sem feature flag). Rollback por revert frontend.
