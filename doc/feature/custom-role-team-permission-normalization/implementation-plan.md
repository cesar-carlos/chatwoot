# Custom Role Team Permission - Normalization Plan (Chatwoot Fork)

## Context

Hoje o projeto atual possui `custom_roles` com estas permissões de conversa:

- `conversation_manage`
- `conversation_unassigned_manage`
- `conversation_participating_manage`

No fork de referência existe uma regra intermediária já implementada:

- `conversation_team_unassigned_manage`

Essa permissão cobre o gap de negócio entre:

1. ver todos os não atribuídos (`conversation_unassigned_manage`)
2. ver apenas os meus (`conversation_participating_manage`)

Permitindo ver:

- conversas atribuídas ao próprio agente
- conversas não atribuídas apenas dos times do agente

## Related features

- **Caixa de Entrada (Inbox View):** permissão dedicada `inbox_view_manage` para controlar se o agente vê o feed de notificações / mensagens recentes — ver [`../custom-role-inbox-view-permission/implementation-plan.md`](../custom-role-inbox-view-permission/implementation-plan.md). Independente desta feature de escopo de conversas por time.

## Objective

Normalizar as regras de negócio de permissões de conversa por custom role no nosso projeto, com rollout seguro e compatível com nosso padrão de fork.

Objetivos específicos:

1. Introduzir `conversation_team_unassigned_manage` ponta a ponta
2. Garantir hierarquia de permissões estável (backend + frontend)
3. Evitar regressões de navegação/guardas de rota
4. Preservar compatibilidade com Enterprise e fluxo atual de custom roles
5. Documentar e validar cenários de negócio em checklist executável

## Scope and Non-Goals

### In Scope

- Normalização das regras de permissão de conversas para custom roles
- Backend: model, filtros e policy
- Frontend: constantes, filtro local, rota de conversas e i18n
- Ajustes de UX relacionados ao entendimento do escopo por time (quando estritamente necessários)
- Teste manual funcional orientado a regras de acesso
- Traduções apenas em `en` e `pt_BR` (exceção fork documentada — ver seção Project Rules)

### Out of Scope (Phase 1)

- Refatoração ampla do módulo de conversas
- Mudança de contrato de APIs não relacionadas a permissões
- Novas permissões fora do domínio de conversa
- Rework visual completo do card de conversa
- Traduções para quaisquer outros idiomas além de `en` e `pt_BR`

## Project Rules Applied

- Priorizar isolamento de customização e minimizar drift com upstream.
- Evitar alterações desnecessárias fora dos pontos estritamente impactados.
- Priorizar implementação Ruby em `custom/` (overlay) e evitar editar `app/` e `enterprise/` diretamente quando houver alternativa por `prepend_mod_with`.
- Onde houver edição inevitável em arquivos upstream, marcar linhas com:
  - Ruby: `# FORK: custom role team permission normalization`
  - TS/Vue: `// FORK: custom role team permission normalization`
- Traduções: regra global do projeto limita a `en.json`/`en.yml`; **nesta feature** incluímos também `pt_BR/customRole.json` como exceção fork explícita.
- Foco MVP e happy path primeiro, seguido de hardening.
- Este documento é a fonte única do plano desta feature.

## Current State (Workspace)

Estado atual validado no projeto:

- `conversation_team_unassigned_manage` implementada ponta a ponta (backend + frontend).
- `CustomRole::PERMISSIONS` inclui a nova permissão (com marcador `FORK:` em `enterprise/app/models/custom_role.rb`).
- `PermissionFilterService` aplica hierarquia completa via overlay em `custom/`:
  - `conversation_manage`
  - `conversation_unassigned_manage`
  - `conversation_team_unassigned_manage`
  - `conversation_participating_manage`
- `ConversationPolicy` delega `permits_team_unassigned_manage?` com gate obrigatório de inbox.
- `conversation.routes.js` importa `CONVERSATION_PERMISSIONS` de `permissions.js` (fonte única; evita lista duplicada local).
- Frontend (`permissions.js`, `getRoleFilterContext`, `applyRoleFilter`, i18n en/pt_BR) contempla a regra de time + inbox.
- `Conversations::UnreadCounts::Counter` aplica `team_unassigned_and_mine` via overlay em `custom/` (gap corrigido).
- Specs automatizados backend e frontend passando; validação manual operacional (PR4) aprovada.

## Business Rules to Normalize

### Permission Hierarchy

Ordem proposta (mais ampla -> mais restrita):

1. `conversation_manage`
2. `conversation_unassigned_manage`
3. `conversation_team_unassigned_manage` (nova)
4. `conversation_participating_manage`

### Access Semantics

Com `conversation_team_unassigned_manage`, o agente pode ver:

- conversas atribuídas a ele
- conversas não atribuídas cujo `team_id` pertence a algum time do agente

Não pode ver:

- não atribuídas de outros times
- não atribuídas sem time
- conversas atribuídas a outros agentes

### Inbox Access Gate (Mandatory)

Além da regra por time/permissão, a conversa só pode ser visível se o usuário tiver acesso à inbox da conversa.

Regra proposta:

- condição final de visibilidade = `has_permission_scope && has_inbox_access`
- `has_inbox_access`: inbox da conversa pertence a `user.assigned_inboxes` (ou equivalente no contexto)

Racional:

- evita exposição de conversa por time quando o agente não é membro da inbox
- mantém coerência com o comportamento base de `Conversations::PermissionFilterService`

### Multi-team and No-team

- Multi-team: visualizar não atribuídas de todos os seus times.
- No-team: comportamento efetivo igual a `conversation_participating_manage`.

## Architecture Adapted to Our Fork

## Backend

Arquivos implementados:

| Camada | Arquivo | Papel |
|--------|---------|-------|
| Permissão (upstream mínimo) | `enterprise/app/models/custom_role.rb` | `PERMISSIONS` + `FORK:` |
| Filtro enterprise | `enterprise/app/services/enterprise/conversations/permission_filter_service.rb` | Hierarquia base; delega team ao overlay |
| Filtro fork | `custom/app/services/custom/conversations/permission_filter_service.rb` | `team_unassigned + mine` |
| Policy enterprise | `enterprise/app/policies/enterprise/conversation_policy.rb` | `show?` + stub `permits_team_unassigned_manage?` |
| Policy fork | `custom/app/policies/custom/conversation_policy.rb` | Gate inbox + escopo por time |
| Unread counts hook | `app/services/conversations/unread_counts/counter.rb` | `prepend_mod_with` (`FORK:`) |
| Unread counts fork | `custom/app/services/custom/conversations/unread_counts/counter.rb` | Modo `:team_unassigned_and_mine` |

Diretriz:

- implementar a nova permissão sem alterar contratos existentes;
- preservar fallback para `Conversation.none` quando não houver permissão aplicável.
- manter mudanças upstream mínimas e sempre com marcador `FORK:`.

## Frontend

Arquivos implementados:

- `app/javascript/dashboard/constants/permissions.js` — constantes e `ASSIGNEE_TYPE_TAB_PERMISSIONS`
- `app/javascript/dashboard/store/modules/conversations/helpers.js` — `getRoleFilterContext` + `applyRoleFilter`
- `app/javascript/dashboard/store/modules/conversations/getters.js` — getters consumindo `getRoleFilterContext`
- `app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js` — importa `CONVERSATION_PERMISSIONS`
- `app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue`
- `app/javascript/dashboard/i18n/locale/en/customRole.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/customRole.json`

Diretriz:

- manter consistência entre constantes globais e guards de rota (via import, não duplicar arrays);
- evitar loops de redirecionamento por divergência de permissões.

## Implementation Phases and TODOs

### Progress Summary

- [x] PR1 implemented (backend foundation)
- [x] PR2 implemented (frontend permission graph + fail-closed)
- [x] PR3 implemented (conversation route guards + i18n en/pt_BR)
- [x] PR4 manual operational validation approved (Go)

### Phase 0 - Alignment and Contract Freeze

Goal: fechar regra de negócio e contrato antes de codar.

Tasks:

- [x] Confirmar semântica final da nova permissão com produto/operação
- [x] Confirmar hierarquia oficial de precedência das permissões
- [x] Confirmar comportamento para conversa sem `team_id` (**decidido: negar**)
- [x] Confirmar regra mandatória de acesso à inbox (`assigned_inboxes`) em conjunto com a nova permissão (**decidido: gate obrigatório**)
- [x] Confirmar se UI do card exibirá nome do time nesta entrega ou fase posterior
  (**decidido: exibir no card — Phase 5 implementada**)
- [x] Registrar decisão final de contrato neste documento

Deliverables:

- Regra de autorização fechada e sem ambiguidades (exceto UX opcional de card)

### Phase 1 - Backend Domain and Authorization

Goal: habilitar regra no backend com segurança.

Tasks:

- [x] Adicionar `conversation_team_unassigned_manage` em `CustomRole::PERMISSIONS`
- [x] Atualizar `PermissionFilterService` com branch intermediária da nova permissão
- [x] Implementar filtro `team_unassigned + mine` com escopo por `user.teams`
- [x] Garantir interseção explícita com inboxes acessíveis do usuário (não apenas por team)
- [x] Atualizar `Enterprise::ConversationPolicy` com `permits_team_unassigned_manage?`
- [x] Garantir `inbox_access?` como gate obrigatório na policy para nova permissão
- [x] Validar precedência para não quebrar regras atuais
- [x] Criar/atualizar specs de backend para matriz de autorização (permissão + team + inbox)
- [x] Marcar linhas divergentes com `# FORK: custom role team permission normalization`
- [x] Corrigir `Conversations::UnreadCounts::Counter` para `conversation_team_unassigned_manage` (`team_unassigned_and_mine`, inbox-scoped)

Deliverables:

- Backend aplicando filtro e autorização da nova permissão

### Phase 2 - Frontend Permission Graph Consistency

Goal: normalizar a malha de permissões no frontend.

Tasks:

- [x] Adicionar nova permissão em `AVAILABLE_CUSTOM_ROLE_PERMISSIONS`
- [x] Adicionar constante dedicada (`CONVERSATION_TEAM_UNASSIGNED_PERMISSIONS`)
- [x] Atualizar `CONVERSATION_PERMISSIONS` global
- [x] Atualizar `ASSIGNEE_TYPE_TAB_PERMISSIONS` (aba unassigned)
- [x] Atualizar `applyRoleFilter` para considerar `userTeams`
- [x] Atualizar `applyRoleFilter` para considerar também `userInboxIds` (gate de inbox)
- [x] Definir comportamento fail-closed no frontend: sem `userInboxIds` válidos => negar acesso para custom role
- [x] Atualizar chamadas que consomem `applyRoleFilter` para fornecer `userTeams`
- [x] Atualizar chamadas que consomem `applyRoleFilter` para fornecer `userInboxIds`
- [x] Criar/atualizar testes de `applyRoleFilter` cobrindo `userTeams + userInboxIds + fail-closed`
- [x] Marcar linhas divergentes com `// FORK: custom role team permission normalization`

Deliverables:

- Frontend refletindo exatamente o mesmo grafo de acesso do backend

### Phase 3 - Route Guards and Navigation Safety

Goal: impedir regressão de navegação (incluindo loop de redirect).

Tasks:

- [x] Atualizar `conversation.routes.js` para incluir a nova permissão na constante local
- [x] Revisar guardas que dependem de arrays locais de permissões
- [x] Validar `defaultRedirectPage()` para usuários com apenas a nova permissão (`routeHelpers.spec.js`)
- [x] Criar teste de rota/guard para impedir regressão de redirect loop (`routeHelpers.spec.js`)
- [x] Executar smoke manual de navegação inicial (`/`, `/dashboard`, inbox/team paths)

Deliverables:

- Navegação estável para perfis com a nova permissão

### Phase 4 - i18n and Custom Role UI

Goal: permitir criação/edição da role nova na UI sem texto quebrado.

Tasks:

- [x] Adicionar label i18n em `en/customRole.json`
- [x] Adicionar label i18n equivalente em `pt_BR/customRole.json`
- [x] Não adicionar chaves em outros idiomas nesta entrega
- [x] Validar render da nova permissão no modal de Add/Edit Custom Role
- [x] Validar render na tabela/lista de permissões
- [x] Garantir ausência de hardcoded strings

Deliverables:

- Fluxo de custom role completo com a nova permissão em EN/PT-BR apenas

### Phase 5 - Optional UX Improvement (Team Visibility in Conversation Card)

Goal: reduzir ambiguidade visual sobre por que a conversa está visível.

Tasks:

- [x] Decidir com produto se exibição do nome do time entra nesta release
- [x] Se aprovado, implementar exibição de time no card de conversa
- [x] Ajustar alinhamento/truncamento para evitar overlap com tempo/botões
- [x] Validar comportamento em temas light/dark

Deliverables:

- Indicação visual de time no card clássico (meta row: ícone people-team + nome) e no card expandido (ícone + tooltip), via `ConversationCardTeamMeta` fork

### Phase 6 - Validation, Hardening and Rollout

Goal: liberar com segurança operacional.

Tasks:

- [x] Rodar validação manual dos cenários de permissão (seção abaixo)
- [x] Verificar consistência backend x frontend em todos os cenários críticos
- [x] Validar consistência por IDs (mesmo usuário/cenário retorna mesmo conjunto de conversas no backend e na UI)
- [x] Executar checkpoint de performance em conta com volume representativo (sem aumento material de tempo de listagem)
- [x] Rodar lint dos arquivos JS/Vue alterados
- [x] Rodar checks Ruby dos arquivos backend alterados
- [x] Validar sem regressão de roles existentes
- [x] Executar smoke pós-deploy em homologação com role real
- [x] Definir Go/No-Go e plano de rollback — **Go** (validação manual aprovada)

Deliverables:

- Feature pronta para rollout controlado

## Manual Validation Checklist (Business-Focused)

### Setup

- [x] Criar role com apenas `conversation_team_unassigned_manage`
- [x] Vincular role a agente que pertence a 1+ times
- [x] Preparar conversas:
  - [x] atribuída ao agente
  - [x] não atribuída no time do agente
  - [x] não atribuída no time do agente, mas em inbox sem acesso
  - [x] não atribuída em outro time
  - [x] não atribuída sem time
  - [x] atribuída a outro agente

### Expected Visibility

- [x] Vê conversa atribuída a ele
- [x] Vê não atribuída do seu time
- [x] Não vê conversa do seu time quando a inbox não está em `assigned_inboxes`
- [x] Não vê não atribuída de outro time
- [x] Não vê não atribuída sem time
- [x] Não vê atribuída a outro agente
- [x] Sem `userInboxIds` carregado no frontend, role custom fica em modo fail-closed (não amplia acesso)

### Navigation and Guards

- [x] Login com usuário que só possui a nova permissão
- [x] Acesso ao dashboard sem redirect loop
- [x] Navegação por inbox/team sem erro de permissão inconsistente

### Regression Matrix

- [x] `conversation_manage` continua vendo tudo
- [x] `conversation_unassigned_manage` continua vendo não atribuídas globais + próprias
- [x] `conversation_participating_manage` continua vendo somente próprias
- [x] Sem impacto em permissões de contato, relatório e base de conhecimento

## Risks and Mitigations

1. **Divergência backend/frontend na regra**
   - Mitigação: checklist de consistência por cenário e revisão cruzada de constantes/guards.

2. **Loop de redirecionamento em guards de rota**
   - Mitigação: incluir nova permissão nas listas locais e validar fluxo de entrada com perfil restrito.

3. **Drift com upstream**
   - Mitigação: mudanças mínimas, marcadores `FORK:` e escopo isolado por arquivo.

4. **Interpretação ambígua para conversas sem time**
   - Mitigação: decisão explícita na Phase 0 e testes dedicados.

## Edge Cases and Operational Safeguards

### Data and Backward Compatibility

- [x] Confirmar que não há migração de dados obrigatória para roles existentes
- [x] Validar que roles atuais continuam válidas sem incluir a nova permissão
- [x] Documentar impacto esperado para contas que não usam custom roles

### Deterministic Permission Precedence

- [x] Consolidar ordem única de precedência em backend e frontend:
  - [x] `conversation_manage`
  - [x] `conversation_unassigned_manage`
  - [x] `conversation_team_unassigned_manage`
  - [x] `conversation_participating_manage`
- [x] Garantir comportamento idêntico quando múltiplas permissões coexistirem no mesmo role

### Inbox Access Source of Truth

- [x] Definir fonte única de inbox acessível no backend (`user.inboxes` / `accessible_conversations`)
- [x] Definir fonte equivalente no frontend para `userInboxIds` (`inboxes/getInboxes`)
- [x] Garantir sincronização semântica entre backend e frontend (mesmo critério de acesso)

### Frontend Loading and Stale State

- [x] Definir UX esperada para estado sem `userInboxIds` carregado (fail-closed sem confusão de uso)
- [x] Evitar flash de conversas indevidas durante hidratação inicial de store (skip inbox gate enquanto `inboxes/getUIFlags.isFetching`)
- [x] Validar atualização correta após troca de conta/usuário sem estado residual

### Counts, Filters, and Deep Links

- [x] Validar coerência dos contadores (`mine`, `unassigned`, `all`) com a nova regra — `UnreadCounts::Counter` overlay em `custom/`
- [x] Label badges no modo team via Redis `SINTER(label_inbox_unassigned, team_inbox_unassigned)` + assignee keys (sem chave composta nova)
- [x] Validar filtros (`q`, `team_id`, `inbox_id`, `assignee_type`) sem bypass de autorização
- [x] Validar acesso direto por URL de conversa (deep link) com policy aplicada corretamente

### Observability and Rollback Readiness

- [ ] Definir sinais mínimos de monitoramento pós-release (erros de permissão, volume inesperado de 403/empty states)
- [ ] Preparar checklist de rollback funcional (como restaurar rapidamente visibilidade esperada)
- [ ] Registrar owner e janela de observação após deploy

## Acceptance Criteria

- [x] Nova permissão disponível no cadastro de custom role
- [x] Backend aplica corretamente `team_unassigned + mine`
- [x] Backend exige acesso à inbox como gate adicional
- [x] Backend unread counts (`Conversations::UnreadCounts::Counter`) respeitam `conversation_team_unassigned_manage`
- [x] Frontend aplica filtro equivalente (`team + inbox`) sem inconsistência
- [x] Frontend adota fail-closed quando faltar contexto de inbox
- [x] Frontend permite lista backend-scoped enquanto inboxes ainda estão fetching
- [ ] Usuário com apenas a nova permissão acessa dashboard sem loop
- [x] Testes automatizados mínimos (backend + frontend + rota) cobrindo cenários críticos
- [x] Specs de overlay em `spec/custom/` (policy, permission filter, unread counter)
- [ ] Consistência backend x frontend validada por cenário e conjunto de IDs
- [ ] Matriz de regressão de permissões existentes aprovada
- [x] EN/PT-BR completos para a nova permissão (sem mudanças em outros idiomas)

## Definition of Done

- [ ] Phases 0 a 6 concluídas
- [ ] Checklist manual de negócio executado e aprovado
- [x] Sem erros novos de lint/check nos arquivos alterados
- [ ] Sem regressão de permissões existentes em homologação
- [x] Plano atualizado com correções pós-review (policy Custom `show?`, label sinter, hydration FE, `spec/custom`)

## Known Limitations (Documented)

1. **Participating vs assignee no frontend** — `applyRoleFilter` para `conversation_participating_manage` verifica assignee, não participant (comportamento pré-existente; lista de conversas não traz participants no payload; backend policy aceita participant).
2. **Boot antes do fetch de inboxes iniciar** — Se `isFetching` ainda é `false` e a store de inboxes está vazia antes do dispatch do fetch, o gate continua fail-closed. Após o fetch iniciar (`isFetching: true`), a lista confia no backend até os IDs hidratarem.

## Manual QA Checklist (pós-deploy / homologação)

1. Role só com `conversation_team_unassigned_manage` → dashboard sem lista vazia falsa no boot (enquanto inboxes carregam)
2. Vê unassigned do próprio time + mine; não vê outros times / sem time / inbox sem acesso
3. Badges de label coerentes com unassigned do time (SINTER)
4. Hierarquia: com `conversation_unassigned_manage` junto, prevalece unassigned amplo
5. Deep link para conversa fora do escopo → 403 / unauthorized

## Code Quality Improvements (Applied)

- [x] `getRoleFilterContext` elimina duplicação nos getters de conversa
- [x] `getParticipatingChats` aplica filtro de role
- [x] Fixtures de teste (`customRole`, `permissionsHelper`) incluem `conversation_team_unassigned_manage`
- [x] Comentário explícito no overlay de unread counts sobre limitação de labels

## Suggested Execution Order (Practical)

1. Phase 0 (decisão de regra)
2. Phase 1 (backend)
3. Phase 2 (frontend core)
4. Phase 3 (guards/rotas)
5. Phase 4 (i18n/UI de role)
6. Phase 6 (validação e rollout)
7. Phase 5 (opcional de UX) como incremento separado, se aprovado

## PR Execution Plan (Incremental)

### PR1 - Backend Permission Normalization (Foundation)

Goal: introduzir a regra no backend com gate de inbox e sem regressão.

Scope:

- `CustomRole::PERMISSIONS` com `conversation_team_unassigned_manage`
- `PermissionFilterService` com hierarquia completa e regra `team_unassigned + mine`
- Interseção obrigatória com inboxes acessíveis
- `ConversationPolicy` com verificação da nova permissão e gate de inbox
- Preferência por overlay em `custom/`; upstream only se inevitável

Definition of Ready:

- Decisões da Phase 0 fechadas
- Cenários de negócio aprovados

Definition of Done:

- Regras backend funcionando para os cenários principais
- Specs backend mínimas cobrindo matriz permissão/team/inbox
- Sem regressão nas permissões existentes

Validation:

- Requests de conversa retornando conjunto esperado por perfil
- Sem erro novo em logs para queries de conversa

### PR2 - Frontend Permission Graph + Fail-Closed

Goal: alinhar frontend ao backend sem expandir acesso indevido.

Scope:

- `permissions.js` atualizado com nova permissão e constantes associadas
- `applyRoleFilter` com `userTeams` + `userInboxIds`
- comportamento fail-closed quando contexto de inbox estiver ausente/inválido
- atualização dos pontos que chamam `applyRoleFilter`

Definition of Done:

- Filtro local equivalente ao backend
- Testes de `applyRoleFilter` cobrindo:
  - team match + inbox match
  - team match + inbox sem acesso
  - no-team
  - fail-closed

Validation:

- UI não exibe conversa fora do escopo da role
- Consistência entre lista renderizada e retorno da API

### PR3 - Route Guards + i18n (EN/PT-BR only)

Goal: estabilizar navegação e concluir camada de produto para a nova permissão.

Scope:

- inclusão da nova permissão nas listas locais de rota (`conversation.routes.js`)
- revisão de guardas e `defaultRedirectPage()` para evitar loop
- i18n da nova permissão em:
  - `app/javascript/dashboard/i18n/locale/en/customRole.json`
  - `app/javascript/dashboard/i18n/locale/pt_BR/customRole.json`
- sem alterações em outros idiomas

Definition of Done:

- Usuário com apenas nova permissão acessa dashboard sem loop
- Modal/listagem de custom role exibem label corretamente em EN/PT-BR
- sem hardcoded strings

Validation:

- Smoke de navegação nas rotas de conversa
- Troca de locale `en` e `pt_BR` validada

### PR4 - Reliability, QA and Rollout Gate

Goal: consolidar segurança de release com evidência de confiabilidade.

Scope:

- execução do checklist manual completo
- validação backend x frontend por conjunto de IDs
- checkpoint de performance em conta com volume representativo
- smoke pós-deploy em homologação com role real
- atualização final deste plano com status dos itens

Definition of Done:

- Acceptance Criteria integralmente marcados
- Go/No-Go registrado
- plano de rollback definido

Validation:

- evidências de QA anexadas ao PR
- sem regressão funcional em permissões legadas

## Suggested PR Merge Order

1. PR1 (backend)
2. PR2 (frontend core)
3. PR3 (guards + i18n)
4. PR4 (hardening/validação e liberação)

## PR Description Templates

Use os templates abaixo como base para abrir cada PR desta feature.

### Template - PR1 (Backend Permission Normalization)

Title suggestion:

- `feat(custom-roles): add team-unassigned conversation permission on backend`

Body template:

```md
## Summary
- Introduz `conversation_team_unassigned_manage` na camada backend de custom roles.
- Normaliza a hierarquia de permissões de conversa com gate obrigatório de inbox.
- Mantém comportamento existente das permissões legadas sem quebra de contrato.

## Scope
- [ ] Atualização de `CustomRole::PERMISSIONS`
- [ ] Ajustes no filtro de permissões de conversa (`team_unassigned + mine`)
- [ ] Gate de inbox (`assigned_inboxes`) obrigatório
- [ ] Atualização de policy para a nova permissão
- [ ] Marcação `FORK:` em alterações upstream inevitáveis

## Test Plan
- [ ] Specs backend da matriz permissão/team/inbox
- [ ] Cenário: team match + inbox match (permitir)
- [ ] Cenário: team match + inbox sem acesso (negar)
- [ ] Cenário: no-team (equivalente a participating)
- [ ] Regressão: `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`

## Risks / Notes
- Risco de drift com upstream mitigado por priorização de overlay em `custom/`.
- Sem mudanças de contrato público de API.
```

### Template - PR2 (Frontend Permission Graph + Fail-Closed)

Title suggestion:

- `feat(custom-roles): align frontend filters with team-unassigned permission`

Body template:

```md
## Summary
- Atualiza o grafo de permissões no frontend para suportar `conversation_team_unassigned_manage`.
- Adiciona gate de inbox no filtro local e comportamento fail-closed para contexto incompleto.
- Alinha comportamento visual/local ao backend para evitar inconsistências de acesso.

## Scope
- [ ] Atualização de constantes em `permissions.js`
- [ ] Atualização de `applyRoleFilter` com `userTeams` + `userInboxIds`
- [ ] Regra fail-closed quando `userInboxIds` estiver ausente/inválido
- [ ] Ajuste de chamadas consumidoras do filtro

## Test Plan
- [ ] Testes unitários de `applyRoleFilter`
- [ ] team match + inbox match
- [ ] team match + inbox sem acesso
- [ ] no-team
- [ ] fail-closed

## Risks / Notes
- Mudança limitada ao filtro local; backend continua sendo fonte final de autorização.
```

### Template - PR3 (Route Guards + i18n EN/PT-BR)

Title suggestion:

- `fix(custom-roles): update conversation guards and add en/pt_BR labels`

Body template:

```md
## Summary
- Atualiza guardas/rotas de conversa para reconhecer a nova permissão e evitar redirect loop.
- Conclui i18n da nova permissão no fluxo de custom roles.
- Mantém escopo de tradução restrito a `en` e `pt_BR`.

## Scope
- [ ] Inclusão da nova permissão nas listas locais de rota
- [ ] Revisão de `defaultRedirectPage()` / guardas relacionados
- [ ] i18n em `en/customRole.json`
- [ ] i18n em `pt_BR/customRole.json`
- [ ] Sem alterações em outros idiomas

## Test Plan
- [ ] Usuário com apenas nova permissão acessa dashboard sem loop
- [ ] Navegação nas rotas de conversa funciona normalmente
- [ ] Labels corretos no modal/listagem de custom role em `en`
- [ ] Labels corretos no modal/listagem de custom role em `pt_BR`

## Risks / Notes
- Ponto sensível: navegação inicial e guardas globais/localizados.
```

### Template - PR4 (Reliability, QA, and Rollout Gate)

Title suggestion:

- `chore(custom-roles): finalize reliability checks and rollout gate`

Body template:

```md
## Summary
- Executa validação final de confiabilidade da feature.
- Fecha evidências de consistência backend x frontend e critérios de Go/No-Go.
- Registra plano de rollout/rollback para liberação controlada.

## Scope
- [ ] Execução do checklist manual completo
- [ ] Validação de consistência por conjunto de IDs (backend vs UI)
- [ ] Checkpoint de performance em cenário representativo
- [ ] Smoke pós-deploy em homologação com role real
- [ ] Atualização final do plano com status de aceite/DoD

## Test Plan
- [ ] Todos os acceptance criteria marcados
- [ ] Sem regressão de permissões legadas
- [ ] Sem erro novo relevante em logs

## Go/No-Go
- [ ] GO aprovado
- [ ] Rollback definido e validado
```

## Execution Status Snapshot (Current)

This section tracks what is already implemented/validated in this workspace and what still requires manual operational validation.

### Completed in code

- [x] Backend: `conversation_team_unassigned_manage` added to `CustomRole::PERMISSIONS`
- [x] Backend: permission filter supports `team_unassigned + mine`
- [x] Backend: inbox access remains mandatory in filtering
- [x] Backend: conversation policy enforces inbox gate and team-scope checks for custom role
- [x] Backend: `Conversations::UnreadCounts::Counter` supports `team_unassigned_and_mine` via `custom/` overlay
- [x] Frontend: constants updated with `conversation_team_unassigned_manage`
- [x] Frontend: `getRoleFilterContext` centraliza `userTeams + userInboxIds` nos getters
- [x] Frontend: `getParticipatingChats` aplica `applyRoleFilter` para alinhar com escopo da role
- [x] Frontend: fail-closed behavior when inbox context is unavailable
- [x] Frontend: conversation route guards include new permission
- [x] i18n: new permission label added only in `en` and `pt_BR`

### Automated validation completed

- [x] Backend specs (enterprise permission filter + policy + unread counter): passing
- [x] Frontend specs (conversation helpers + getters + settings helper + permissionsHelper): passing
- [x] Lint diagnostics for modified files: no new issues

### Pending manual validation before Go/No-Go

- [ ] Manual matrix with real users/roles (team, inbox access, no-team, other-team)
- [ ] Deep-link access validation by URL in browser
- [ ] End-to-end UI smoke in settings custom roles flow (create/edit/display)
- [ ] Staging/homologation smoke with real account data
- [ ] Rollback rehearsal and final Go/No-Go registration

