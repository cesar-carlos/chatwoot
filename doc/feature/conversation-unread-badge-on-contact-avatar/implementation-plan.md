# Conversation Unread Badge on Contact Avatar - Implementation Plan (Chatwoot Fork)

## Context

Queremos exibir o total de mensagens não lidas como uma bolinha sobre a foto do contato no card de conversa, conforme referência visual enviada.

Hoje, o total não lido já existe no frontend, mas aparece em locais diferentes:

- card legado (`widgets/conversation/ConversationCard.vue`): contador na coluna da direita
- card novo (`components-next/Conversation/ConversationCard/*`): contador no preview/meta

Não existe implementação atual da bolinha sobre o avatar do contato.

## Objective

Implementar a bolinha de não lidas sobre o avatar do contato, de forma consistente, com mínimo impacto e seguindo as regras do fork:

1. Exibir badge sobre avatar quando `unread_count > 0`
2. Ocultar badge quando `unread_count = 0`
3. Exibir `9+` para valores acima de 9
4. Evitar duplicidade de contador no mesmo card
5. Manter comportamento atual de hover/seleção/checkbox

## Scope and Non-Goals

### In Scope

- Lista principal de conversas (card legado)
- Histórico de conversas em áreas que usam card novo
- Reuso de componente visual para badge
- Ajustes mínimos de layout para evitar sobreposição indesejada

### Out of Scope

- Alterar regra de cálculo de mensagens não lidas no backend
- Mudar APIs de conversas
- Introduzir feature flag global
- Rework completo de layout dos cards

## Project Rules Applied

- Alterações em arquivos upstream somente quando inevitável
- Linhas divergentes do upstream marcadas com `// FORK: unread badge over avatar`
- Tailwind only (sem CSS custom, sem inline styles novos)
- Implementação MVP, happy path primeiro
- Sem novos docs além deste plano

## Current State (Relevant)

### Legado (lista principal)

- Arquivo: `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- Fonte de verdade: `props.chat.unread_count`
- Já renderiza contador, porém na coluna direita do card
- Avatar do contato já está dentro de container `relative` (bom ponto para ancorar badge)

### Components-next (history/listagens modernas)

- Arquivo: `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue`
- Badge de não lidas está nos componentes de preview:
  - `CardMessagePreview.vue`
  - `CardMessagePreviewWithMeta.vue`
- Avatar principal do contato é renderizado sem contador sobreposto

## Technical Design

### 1) Componente reutilizável de badge

Criar:

- `app/javascript/dashboard/components-next/Conversation/ConversationCard/UnreadCountBadge.vue`

Contrato proposto:

- `props.count` (Number, required)
- renderiza somente quando `count > 0`
- texto exibido: `count > 9 ? '9+' : count`
- estilo base circular pequeno com contraste alto
- suporte a uso em container `relative` com classes de posicionamento externas

Decisão:

- manter componente puramente visual (sem store, sem i18n)
- posicionamento controlado pelo pai para máxima flexibilidade

### 2) Card legado: mover indicador para sobre o avatar

Arquivo:

- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`

Mudanças:

1. Importar e usar `UnreadCountBadge.vue`
2. Renderizar badge dentro do container do avatar (que já é `relative`)
3. Remover/ocultar contador da coluna direita para evitar duplicidade
4. Garantir que overlay de seleção do avatar continue funcional

Notas:

- Alterações nesse arquivo são upstream edits inevitáveis
- Todas as linhas alteradas recebem `// FORK: unread badge over avatar`

### 3) Card novo: padronizar badge no avatar do contato

Arquivos:

- `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue`
- `app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreview.vue`
- `app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue`

Mudanças:

1. Em `ConversationCard.vue`, adicionar badge sobre avatar principal do contato
2. Em `CardMessagePreview.vue`, remover badge atual do bloco de preview
3. Em `CardMessagePreviewWithMeta.vue`, remover badge atual do bloco de preview

Racional:

- contador deve estar associado ao contato/conversa, não ao preview/meta
- reduz variação visual entre variantes de card

## UX and Visual Behavior

- Badge no canto superior direito do avatar (com offset pequeno)
- Prioridade visual: legibilidade em tema claro/escuro
- Tamanho fixo compatível com avatares de 24 e 40 px
- Valor grande simplificado para `9+`

## Data and Contracts

- Não há mudanças de contrato com backend
- Campos utilizados permanecem:
  - legado: `chat.unread_count`
  - components-next: `conversation.unreadCount`

## Performance Considerations

- Render condicional simples (`count > 0`)
- Sem watchers extras
- Sem loops novos
- Sem chamadas de rede adicionais

## Reliability Hardening

1. **Normalização do valor unread em um único ponto**
   - Criar função/computed local por card para normalizar o count:
     - legado: `chat.unread_count`
     - components-next: `conversation.unreadCount`
   - Regra: valor inválido (`null`, `undefined`, string não numérica, negativo) vira `0`.

2. **Componente de badge fail-safe**
   - `UnreadCountBadge.vue` concentra as regras de confiabilidade:
     - `safeCount = Number(count) || 0`
     - clamp mínimo em `0`
     - render apenas com `safeCount > 0`
     - label `safeCount > 9 ? '9+' : safeCount`
   - Evita lógica duplicada em múltiplos cards.

3. **Não interferir em interações do avatar**
   - Badge com `pointer-events-none` para não bloquear:
     - clique no card
     - hover
     - checkbox/overlay de seleção no card legado
   - Garantir `z-index` adequado para visibilidade sem quebrar overlay.

4. **Atualização confiável em tempo real**
   - Validar que alterações de leitura via websocket/store atualizam badge sem stale UI.
   - Revisar dependências reativas dos cards para evitar inconsistência visual.

5. **Cobertura mínima de teste de componente**
   - Casos: `0`, `1`, `9`, `10`, `null`, `undefined`, `-1`, `'3'`.
   - Assertivas:
     - render/ocultação correta
     - texto correto (`9+` para > 9)
     - classes essenciais do badge

## Enterprise / Compatibility Considerations

- Mudança é somente de apresentação no frontend
- Não altera fluxo de dados nem permissões
- Baixo risco de drift com Enterprise, ainda assim revisar se há overrides de card em `enterprise/`

## Implementation Steps

### Phase 1 - Build reusable badge

1. Criar `UnreadCountBadge.vue`
2. Adicionar story simples (opcional, se já houver cobertura em Storybook do card)

### Phase 2 - Apply on legacy card

1. Integrar badge no avatar de `widgets/conversation/ConversationCard.vue`
2. Remover badge da coluna direita
3. Validar hover, seleção e checkbox

### Phase 3 - Apply on components-next card

1. Integrar badge no avatar em `ConversationCard.vue`
2. Remover badges de preview/meta
3. Validar variantes com/sem labels e com/sem SLA

### Phase 4 - Validation

1. Rodar lint JS dos arquivos alterados
2. Teste manual dos cenários principais
3. Ajustes finos de espaçamento/posição
4. Validar fluxos de confiabilidade (invalid count, realtime update, interação de avatar)

## Manual Test Plan

1. Abrir lista principal com conversas:
   - unread 0 -> sem badge
   - unread 1..9 -> badge com número
   - unread >9 -> `9+`
2. Selecionar conversa (checkbox/overlay do avatar) e confirmar que badge não quebra interação
3. Alterar estado de leitura em tempo real e verificar atualização do badge
4. Validar histórico de contato (cards components-next)
5. Testar tema light/dark
6. Testar resolução comum desktop (sem objetivo mobile nesta fase)
7. Simular valores inesperados no fixture/local state (`null`, `undefined`, negativo, string) e confirmar fallback seguro

## Risks and Mitigations

1. **Risco:** sobreposição visual com overlay/checkbox no avatar legado  
   **Mitigação:** testar hover/selected e ajustar `z-index`/offset utilitários

2. **Risco:** duplicidade de badges em variantes de card  
   **Mitigação:** remover contador dos previews após mover para avatar

3. **Risco:** divergência em merge upstream  
   **Mitigação:** marcar todas linhas alteradas com `// FORK: unread badge over avatar`

## Acceptance Criteria

- Badge exibida sobre avatar do contato em cards do escopo
- Sem badge quando não há não lidas
- Exibição `9+` para contagens altas
- Sem duplicidade de contador no mesmo card
- Sem regressão de clique/hover/seleção
- Lint sem novos erros nos arquivos alterados
- Fallback seguro para valores inválidos de unread sem erro de render
- Atualização reativa correta após mark-as-read/unread em tempo real

## Rollout Strategy

- Entrega direta (sem feature flag), por ser alteração visual de baixo risco
- Caso haja regressão, rollback simples por revert frontend

## Deliverables

1. Novo componente `UnreadCountBadge.vue`
2. Ajustes no card legado
3. Ajustes no card components-next e remoção de badges antigos de preview
4. Validação manual registrada no PR

## Open Questions

1. Confirmar posição final exata no avatar: canto superior direito ou superior esquerdo?
2. Confirmar limite visual: `9+` (proposto) ou `99+`?
3. Precisamos manter o contador da coluna direita em algum contexto específico?

## Estimated Effort

- Implementação: 1 a 2 horas
- Ajustes visuais e QA manual: 30 a 60 minutos
- Total estimado: até meio período
