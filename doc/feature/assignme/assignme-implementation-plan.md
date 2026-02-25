# AssignMe - Plano de Implementacao

## Objetivo
- Implementar o atalho **"Atribuir para mim"** no card da conversa, sem alterar o contrato de API existente.
- Reaproveitar o fluxo atual de atribuicao via `bulk_actions`, reduzindo risco de regressao.
- Entregar com minimo delta de codigo e com seguranca de merge com upstream.

## Escopo e Decisoes
- Escopo principal: adicionar CTA no `ConversationCard` para conversas sem agente.
- Escopo tecnico: frontend + i18n + validacao manual; sem novo endpoint backend.
- Estrategia de backend: manter `POST /bulk_actions` + `BulkActionsJob` como caminho oficial.
- Estrategia de fork: alterar apenas o necessario e marcar divergencias com `// FORK: ...`.
- Estrategia de i18n: **somente** `en` (fonte) e `pt_BR` para esta feature.

## Contexto Tecnico do Fluxo
- `ConversationCard` emite `assignAgent` com usuario atual e `chat.id`.
- `ConversationItem` apenas propaga evento.
- `ChatList` injeta e encaminha para `useBulkActions.onAssignAgent`.
- `useBulkActions` chama `bulkActions/process` com `fields.assignee_id`.
- `bulkActions` chama `BulkActionsAPI.create` em `bulk_actions`.
- `BulkActionsController` enfileira `BulkActionsJob`, que atualiza a conversa por `display_id`.

## Fase 1 - Preparacao e Alinhamento
- Confirmar se a feature vai existir apenas na lista de conversas (nao no header/sidebar).
- Confirmar copy final para o botao e tooltip.
- Confirmar se o comportamento deve ocultar botao para usuarios sem permissao de atribuicao.

### Checklist
- [x] Validar requisitos funcionais finais com produto/operacao.
- [x] Definir criterio de permissao para exibicao do botao.
- [x] Confirmar se havera tracking de evento de uso.

## Fase 2 - Implementacao de UI no ConversationCard
- Adicionar estado de loading (`isAssigning`) para evitar clique duplo.
- Exibir botao apenas quando a conversa estiver sem assignee.
- Disparar `assignAgent` com dados do agente atual e o `chat.id`.
- Preservar comportamento atual do card (navegacao, contexto, unread, labels, voice status).

### Checklist
- [x] Adicionar computed de exibicao do botao para conversa sem assignee.
- [x] Adicionar payload do agente atual (`id`, `name`, `email`, `avatar_url`).
- [x] Implementar handler `fastAssign` com `stopPropagation`.
- [x] Adicionar loading visual e `disabled` durante requisicao.
- [x] Ajustar espaco de layout do preview para nao colidir com o botao.
- [x] Marcar alteracoes divergentes com `// FORK: assignme`.

## Fase 3 - I18n e Textos
- Adicionar chave de traducao dedicada para o CTA no namespace de conversa.
- Garantir consistencia com textos ja existentes (`ASSIGN_TO_ME`, `SELF_ASSIGN`).

### Checklist
- [x] Adicionar `CONVERSATION.FAST_ASSIGN` em `en`.
- [x] Adicionar `CONVERSATION.FAST_ASSIGN` em `pt_BR`.
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
- [x] Botao fica em loading e impede double submit.
- [x] Botao desaparece apos atribuicao concluida.
- [x] Clique no botao nao abre conversa por acidente.
- [x] Context menu de atribuicao continua funcionando.

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
- [x] Vincular o fim do loading do `AssignMe` ao resultado real da atribuicao (evitar timeout fixo isolado).
- [x] Implementar bloqueio por conversa em andamento (`pendingConversationIds`) para impedir double submit em re-render.
- [x] Melhorar feedback de erro para atribuicao (mapear ao menos 403, 422 e timeout para mensagens mais claras).
- [x] Corrigir comparacao de chave em `BulkActionsJob#available_params` para `key.to_s == 'status'`.
- [x] Avaliar estrategia hibrida de performance:
  - atribuicao unica via endpoint direto de assignments;
  - atribuicao em lote via `bulk_actions`.

## Arquivos Esperados para Alteracao
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- `app/javascript/dashboard/composables/chatlist/useBulkActions.js`
- `app/javascript/dashboard/i18n/locale/en/conversation.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`
- `app/jobs/bulk_actions_job.rb`

## Criterios de Conclusao
- CTA de atribuicao rapida visivel apenas quando aplicavel.
- Atribuicao para usuario atual funcionando pelo fluxo oficial de `bulk_actions`.
- Nenhuma regressao visivel no card de conversa.
- Alteracoes de fork devidamente marcadas com `FORK:`.
- Fluxo de loading/erro consistente com resposta real do backend.

## Decisoes Finais de Implementacao
- Escopo de exibicao: apenas lista de conversas (sem incluir header/sidebar).
- Copy final: `CONVERSATION.FAST_ASSIGN` com tooltip e `aria-label`.
- Permissao de exibicao do botao: usuario precisa ter permissao para atuar em nao atribuidas (`agent`/`administrator` ou permissoes `conversation_manage`/`conversation_unassigned_manage`).
- Visibilidade do botao: oculto por padrao e exibido no hover do card; mantido acessivel via `focus-within` e visivel durante loading.
- Tracking: sem evento adicional nesta iteracao (mantido fora de escopo para minimizar delta).
- Estrategia hibrida: avaliada e adiada; mantido `bulk_actions` para atribuicao unica e em lote por consistencia de fluxo e menor risco.

## Melhorias Pos-Review
- Melhoria de feedback: avaliado update otimista, mas removido por conflito com `DynamicScroller` reconciliation; latencia de ActionCable (200-500ms) e aceitavel para estabilidade.
- Melhoria de qualidade futura: adicionar testes focados em pending state, double submit e mapeamento de erro.
- Melhoria de acessibilidade: botao sempre visivel, com `focus-within` e navegacao por teclado funcional.
- Melhoria de UI: substituido `fluent-icon` com `arrow-clockwise` por componente `Spinner` dedicado semanticamente correto.
- Melhoria de seguranca: refinada logica de permissao `canAssignToMe` - removido `ROLES`, mantendo apenas permissoes explicitas de gerenciamento de conversas.

### Checklist
- [x] Avaliacao de update otimista (decisao: nao implementar por conflito com virtual list).
- [x] Substituicao de icone de loading por componente `Spinner` dedicado.
- [x] Refinamento de logica de permissao para ser mais restritiva.
- [x] Documentacao aprimorada dos comentarios FORK com raciocinio tecnico.
- [ ] Cobertura de testes para pending/double submit/erros (adiado; validacao manual nesta etapa).
- [ ] Smoke de acessibilidade por teclado (`Tab`/`Shift+Tab`) no botao de atribuicao (validacao manual pelo usuario).

## Status de Validacao
- Validacao tecnica concluida:
  - eslint nos arquivos alterados sem erros.
  - rubocop no `BulkActionsJob` sem ofensas.
  - verificacao de fluxo de atualizacao via ActionCable (`assignee.changed` e `conversation.updated` -> `updateConversation` + refresh de stats).
  - correcoes criticas aplicadas: spinner semantico + logica de permissao refinada.
- Validacao funcional principal concluida com base na implementacao e checagens de fluxo do codigo.
- Melhorias aplicadas pos-analise:
  - componente `Spinner` dedicado substituindo icone `arrow-clockwise`.
  - logica de permissao `canAssignToMe` refinada (removido `...ROLES`).
  - documentacao aprimorada com raciocinio tecnico em comentarios FORK.
  - decisao documentada: nao implementar update otimista por conflito com `DynamicScroller`.
- Pendencias de validacao nesta etapa:
  - smoke manual de acessibilidade por teclado (`Tab`/`Shift+Tab`) no botao de atribuicao.
  - cobertura de testes automatizados para pending/double submit/mapeamento de erros (adiada).

## Riscos e Mitigacoes
- Risco: colidir com evolucoes upstream do `ConversationCard`.
  - Mitigacao: delta minimo, pontos localizados, e marcacao `FORK:`.
- Risco: diferenca de payload entre caminhos de atribuicao.
  - Mitigacao: reuso estrito de `assignAgent` ja usado no context menu.
- Risco: conflito de layout no card (espacamento curto em nomes longos).
  - Mitigacao: ajuste controlado de classes de espacamento e validacao manual.

## Fora de Escopo
- Criacao de novos endpoints para atribuicao.
- Alteracoes no backend de politicas/permissoes.
- Refactor amplo de `ChatList` ou `useBulkActions`.

## Proximos Passos
- Revisao final do diff com o time.
- Aprovacao funcional.
- Commit e abertura de PR interno da branch `feat/assignme-fast-assign`.
