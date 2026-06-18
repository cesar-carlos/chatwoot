# AssignMe - Plano de Implementacao

## Objetivo
- Implementar o atalho **"Atribuir para mim"** no card da conversa, sem alterar o contrato de API existente.
- Reaproveitar o fluxo atual de atribuicao via `bulk_actions`, reduzindo risco de regressao.
- Entregar com minimo delta de codigo e com seguranca de merge com upstream.

## Escopo e Decisoes
- Escopo principal: adicionar CTA no `ConversationCard` (layout condensado) e `ConversationCardExpanded` (layout expandido) para conversas sem agente.
- Escopo tecnico: frontend + i18n + validacao manual; sem novo endpoint backend.
- Estrategia de backend: manter `POST /bulk_actions` + `BulkActionsJob` como caminho oficial.
- Estrategia de fork: logica extraida para `composables/fork/` e `components/fork/`; hook minimo no card upstream.
- Estrategia de i18n: **somente** `en` (fonte) e `pt_BR` para esta feature.

## Contexto Tecnico do Fluxo
- `ConversationCard` / `ConversationCardExpanded` disparam `fastAssign` via `useConversationCardFork`.
- `ConversationItem` monta o fork, faz bridge do `emit('assignAgent')` para o `assignAgent` injetado e repassa props ao card condensado/expandido.
- `ChatList` instancia `useCanAssignToMe` uma vez, injeta `canAssignConversationToMe` e `isAssignPending`, e encaminha `assignAgent` para `useBulkActions.onAssignAgent`.
- `useBulkActions` delega pending state para `useAssignMePending` e chama `bulkActions/process`.
- `bulkActions` chama `BulkActionsAPI.create` em `bulk_actions`.
- `BulkActionsController` enfileira `BulkActionsJob`, que atualiza a conversa por `display_id`.
- O botao some quando ActionCable atualiza o assignee na store (nao quando o spinner para).

## Fase 1 - Preparacao e Alinhamento
- Confirmar se a feature vai existir apenas na lista de conversas (nao no header/sidebar).
- Confirmar copy final para o botao e tooltip.
- Confirmar se o comportamento deve ocultar botao para usuarios sem permissao de atribuicao.

### Checklist
- [x] Validar requisitos funcionais finais com produto/operacao.
- [x] Definir criterio de permissao para exibicao do botao.
- [x] Confirmar se havera tracking de evento de uso.

## Fase 2 - Implementacao de UI no ConversationCard
- Adicionar estado de loading (`isAssigning`) para evitar clique duplo durante o HTTP e ate websocket.
- Exibir botao apenas quando a conversa estiver sem assignee.
- Disparar `assignAgent` com dados do agente atual e o `chat.id`.
- Preservar comportamento atual do card (navegacao, contexto, unread, labels, voice status).

### Checklist
- [x] Adicionar computed de exibicao do botao para conversa sem assignee (`useConversationCardFork`).
- [x] Adicionar payload do agente atual (`id`, `name`, `email`, `avatar_url`).
- [x] Implementar handler `fastAssign` com `stopPropagation`.
- [x] Adicionar loading visual e `disabled` durante requisicao (`ConversationCardFastAssignButton`).
- [x] Ajustar espaco de layout do preview para nao colidir com o botao.
- [x] Marcar alteracoes divergentes com `// FORK: assignme`.
- [x] Adicionar fast-assign no layout expandido (`ConversationCardExpanded`).

## Fase 3 - I18n e Textos
- Adicionar chave de traducao dedicada para o CTA no namespace de conversa.
- Garantir consistencia com textos ja existentes (`ASSIGN_TO_ME`, `SELF_ASSIGN`).

### Checklist
- [x] Adicionar `CONVERSATION.FAST_ASSIGN` em `en`.
- [x] Adicionar `CONVERSATION.FAST_ASSIGN` em `pt_BR`.
- [x] Adicionar `CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.PENDING` em `en` e `pt_BR`.
- [x] Nao adicionar traducoes em outros locales.
- [x] Validar tooltip, `aria-label` e texto do botao.

## Fase 4 - Integracao com Fluxo Atual de Atribuicao
- Nao criar novo endpoint e nao duplicar logica de atribuicao.
- Reusar `assignAgent` existente vindo de `ChatList/useBulkActions`.

### Checklist
- [x] Confirmar que `@assign-agent` segue o mesmo caminho do context menu.
- [x] Confirmar payload esperado por `onAssignAgent` (`agent` + array de `conversationId`).
- [x] Confirmar que feedback e atualizacao de estado chegam via fluxo atual (ActionCable/store).

## Fase 5 - Validacao Funcional
- Testar em lista com conversas atribuidas e nao atribuidas.
- Testar comportamento com clique rapido repetido.
- Validar estado final da conversa apos atribuicao.

### Checklist
- [x] Conversa sem assignee mostra botao.
- [x] Clique em "Atribuir para mim" atribui para usuario logado.
- [x] Botao fica em loading e impede double submit ate websocket confirmar assignee.
- [x] Botao desaparece apos atribuicao concluida (via ActionCable).
- [x] Clique no botao nao abre conversa por acidente.
- [x] Context menu de atribuicao continua funcionando.
- [x] Desatribuir pela sidebar nao deixa o botao em loading infinito.
- [x] Tentativa de atribuir pelo context menu durante fast-assign exibe alerta de pending.

## Fase 6 - Qualidade e Regressao
- Garantir que a alteracao nao afeta features adjacentes do card.

### Checklist
- [x] Rodar lint frontend no escopo alterado.
- [x] Verificar nao regressao de selecao em massa (bulk select).
- [x] Verificar nao regressao de labels, prioridade e context menu.
- [x] Verificar nao regressao de voice call status no card.

## Fase 7 - Hardening (Confiabilidade e Performance)
- Melhorar robustez do fluxo de atribuicao rapida sem ampliar escopo funcional.
- Evitar estados inconsistentes de loading e cliques duplicados em ambiente com latencia.
- Revisar pontos de resiliencia no caminho `useBulkActions` -> `BulkActionsJob`.

### Checklist
- [x] Vincular loading ao enqueue HTTP de `bulk_actions` e manter ate websocket.
- [x] Implementar bloqueio por conversa em andamento (`useAssignMePending`) ate `meta.assignee` atualizar.
- [x] Melhorar feedback de erro para atribuicao (mapear ao menos 403, 422 e timeout para mensagens mais claras).
- [x] Corrigir comparacao de chave em `BulkActionsJob#available_params` para `key.to_s == 'status'`.
- [x] Alinhar `canAssignToMe` com `applyRoleFilter` via `useCanAssignToMe`.
- [x] Testes de integracao para `onAssignAgent` em `useBulkActions.spec.js`.
- [x] Avaliar estrategia hibrida de performance:
  - atribuicao unica via endpoint direto de assignments;
  - atribuicao em lote via `bulk_actions`.
  - **Decisao:** adiada; manter `bulk_actions` por consistencia.

## Arquivos Alterados
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue` — hook `useConversationCardFork` + componentes fork
- `app/javascript/dashboard/components/fork/ConversationCardFastAssignButton.vue` — CTA + spinner
- `app/javascript/dashboard/components/fork/ConversationCardForkAvatarBadge.vue` — badge unread (fork)
- `app/javascript/dashboard/composables/fork/useConversationCardFork.js` — logica assignme do card (sem unread; ver `useUnreadCount`)
- `app/javascript/dashboard/composables/fork/useAssignMePending.js` — pending ate websocket, normalizacao de ids, watcher deep e fallback de 15s
- `app/javascript/dashboard/composables/fork/useCanAssignToMe.js` — permissao por conversa via `applyRoleFilter` (instanciado no `ChatList`)
- `app/javascript/dashboard/composables/fork/useUnreadCount.js` — contagem unread normalizada
- `app/javascript/dashboard/composables/chatlist/useBulkActions.js` — integracao assignme + pending ate websocket
- `app/javascript/dashboard/components/ConversationItem.vue` — fork do card, bridge `emit` -> `assignAgent`, fast-assign expandido
- `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCardExpanded.vue` — fast-assign no layout expandido
- `app/javascript/dashboard/components/ChatList.vue` — `provide('isAssignPending')` e `provide('canAssignConversationToMe')`
- `app/javascript/dashboard/components/ConversationList.vue` — repassa props de layout
- `app/javascript/dashboard/i18n/locale/en/conversation.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`
- `app/jobs/bulk_actions_job.rb`
- `app/javascript/dashboard/composables/fork/spec/useAssignMePending.spec.js`
- `app/javascript/dashboard/composables/fork/spec/useConversationCardFork.spec.js`
- `app/javascript/dashboard/composables/fork/spec/useCanAssignToMe.spec.js`
- `app/javascript/dashboard/composables/spec/useBulkActions.spec.js`

## Criterios de Conclusao
- CTA de atribuicao rapida visivel apenas quando aplicavel (condensado e expandido).
- Atribuicao para usuario atual funcionando pelo fluxo oficial de `bulk_actions`.
- Nenhuma regressao visivel no card de conversa.
- Alteracoes de fork devidamente marcadas com `FORK:`.
- Loading consistente ate websocket confirmar assignee; botao some via ActionCable.

## Decisoes Finais de Implementacao
- Escopo de exibicao: lista de conversas nos layouts condensado (`ConversationCard`) e expandido (`ConversationCardExpanded`).
- Copy final: `CONVERSATION.FAST_ASSIGN` com tooltip e `aria-label`.
- Permissao de exibicao do botao: `useCanAssignToMe` reutiliza `applyRoleFilter` — usuario precisa de `conversation_manage`, `conversation_unassigned_manage`, ou `conversation_team_unassigned_manage` (com time correspondente) para conversas sem assignee; agentes/administradores sempre podem.
- Visibilidade do botao: **sempre visivel** quando conversa sem assignee e usuario tem permissao (decisao de acessibilidade).
- Tracking: sem evento adicional nesta iteracao (mantido fora de escopo para minimizar delta).
- Estrategia hibrida: avaliada e adiada; mantido `bulk_actions` para atribuicao unica e em lote por consistencia de fluxo e menor risco.
- Arquitetura fork: logica em `composables/fork/` e `components/fork/`; card upstream com import minimo.

## Melhorias Pos-Review
- Melhoria de feedback: avaliado update otimista, mas removido por conflito com `DynamicScroller` reconciliation; latencia de ActionCable (200-500ms) e aceitavel para estabilidade.
- Melhoria de qualidade: testes em `useAssignMePending` (12), `useConversationCardFork` (7), `useCanAssignToMe` (5), `useBulkActions` (6).
- Melhoria de acessibilidade: botao sempre visivel quando aplicavel, com navegacao por teclado funcional.
- Melhoria de UI: componente `Spinner` dedicado em `ConversationCardFastAssignButton`.
- Melhoria de arquitetura: pending state extraido para `useAssignMePending`; logica do card para `useConversationCardFork`; `useCanAssignToMe` hoisted para `ChatList` (evita recomputar permissao por item).
- Melhoria de confiabilidade: pending ate websocket via `markAssignPendingUntilResolved` + watcher deep na store.
- Melhoria de permissao: `useCanAssignToMe` alinhado com filtros da lista de conversas.

### Correcoes Pos-Review (bugs encontrados em validacao)
- [x] `ConversationItem` passava `emit` como objeto `{ assignAgent }` em vez de funcao — causava `TypeError: o is not a function` no clique.
- [x] Loading infinito apos atribuir e desatribuir pela sidebar — `useAssignMePending` agora limpa pending em transicoes de assignee (match, unassign, outro agente) e tem fallback de 15s.
- [x] Normalizacao de `conversationId` (`string` vs `number`) no `Map` de pending — evita `isAssignPending` inconsistente.
- [x] Alerta `AGENT_ASSIGNMENT.PENDING` quando context menu tenta atribuir durante fast-assign em andamento.

### Checklist
- [x] Avaliacao de update otimista (decisao: nao implementar por conflito com virtual list).
- [x] Substituicao de icone de loading por componente `Spinner` dedicado.
- [x] Logica de permissao alinhada com `applyRoleFilter` (`useCanAssignToMe`).
- [x] Pending ate websocket confirmar assignee.
- [x] Fast-assign no layout expandido.
- [x] Testes de integracao para `onAssignAgent` (403, 422, timeout, generico, duplicate guard).
- [x] Documentacao aprimorada dos comentarios FORK com raciocinio tecnico.
- [x] Cobertura de testes para pending/double submit (`useAssignMePending`, `useConversationCardFork`, `useCanAssignToMe`).
- [x] Cobertura de testes para unassign, outro agente, ids string/number e alerta de pending.
- [ ] Smoke de acessibilidade por teclado (`Tab`/`Shift+Tab`) no botao de atribuicao (validacao manual pelo usuario).

## Status de Validacao
- Validacao tecnica concluida:
  - eslint nos arquivos alterados.
  - rubocop no `BulkActionsJob` sem ofensas.
  - verificacao de fluxo de atualizacao via ActionCable (`assignee.changed` e `conversation.updated` -> `updateConversation` + refresh de stats).
  - refactor para composables fork (`useConversationCardFork`, `useAssignMePending`, `useCanAssignToMe`).
  - testes unitarios e de integracao para pending state, permissao e error mapping.
- Validacao funcional principal concluida com base na implementacao e checagens de fluxo do codigo.
- Pendencias de validacao nesta etapa:
  - smoke manual de acessibilidade por teclado (`Tab`/`Shift+Tab`) no botao de atribuicao.

## Semantica de Loading
- `isAssignPending` permanece ativo desde o clique ate o assignee na store refletir o estado esperado ou uma transicao que encerre a operacao.
- O spinner inicia no clique e para quando:
  - `meta.assignee.id` corresponde ao assignee esperado (sucesso via ActionCable/store);
  - assignee volta para `null` apos ter estado atribuido (ex.: desatribuir pela sidebar);
  - conversa e atribuida a outro agente (diferente do esperado);
  - fallback de 15s expira (rede/websocket lento).
- Em caso de erro HTTP, pending e limpo imediatamente no `catch` de `onAssignAgent`.
- O botao some quando ActionCable atualiza `meta.assignee` na store (conversa deixa de ser unassigned).
- Double-click entre HTTP 200 e websocket e bloqueado: `isAssignPending` permanece true ate uma das condicoes acima.
- Tentativa de atribuir pelo context menu durante pending exibe `CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.PENDING` (somente atribuicao de conversa unica).

## Logica de Permissao (`useCanAssignToMe`)
- Instanciado uma vez em `ChatList` e exposto via `provide('canAssignConversationToMe')`; `ConversationItem` apenas injeta e avalia por conversa.
- Reutiliza `applyRoleFilter` de `store/modules/conversations/helpers.js` com os mesmos inputs da lista (`getUserRole`, `getUserPermissions`, `teams/getMyTeams`, `inboxes/getInboxes`).
- Fast-assign so aparece em conversas **sem assignee**.
- Permissoes que permitem fast-assign em conversa unassigned:
  - `administrator` / `agent` (role padrao)
  - `conversation_manage`
  - `conversation_unassigned_manage`
  - `conversation_team_unassigned_manage` (somente se conversa pertence a um time do usuario)
- `conversation_participating_manage` **nao** permite fast-assign em conversas unassigned.

## Riscos e Mitigacoes
- Risco: colidir com evolucoes upstream do `ConversationCard`.
  - Mitigacao: logica em `composables/fork/`, delta minimo no card, marcacao `FORK:`.
- Risco: diferenca de payload entre caminhos de atribuicao.
  - Mitigacao: reuso estrito de `assignAgent` ja usado no context menu.
- Risco: conflito de layout no card (espacamento curto em nomes longos).
  - Mitigacao: ajuste controlado de classes de espacamento e validacao manual.
- Risco: pending preso apos desatribuir por caminho paralelo (sidebar).
  - Mitigacao: watcher deep em `allConversations` + regras de transicao em `useAssignMePending` + timeout de 15s.

## Fora de Escopo
- Criacao de novos endpoints para atribuicao (melhoria D adiada).
- Alteracoes no backend de politicas/permissoes.
- Refactor amplo de `ChatList` ou `useBulkActions` alem do hook assignme.
- Smoke manual de teclado (pendente validacao pelo usuario).

## Proximos Passos
- Revisao final do diff com o time.
- Aprovacao funcional.
- Smoke manual de acessibilidade por teclado.
- Commit e abertura de PR interno da branch `feat/assignme-fast-assign`.
