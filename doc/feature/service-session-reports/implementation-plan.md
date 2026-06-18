# Service Session Reports - Implementation Plan (Chatwoot Fork)

## Context

Temos um plano já implementado para `conversation-single-history-per-channel` que corrige comportamento por ciclo quando `inbox.lock_to_single_conversation = true`:

- resolução por ciclo (`conversation_resolved`)
- primeira resposta por ciclo (`first_response`)
- CSAT por ciclo
- seleção de conversa centralizada por `Conversations::Resolver`

Agora queremos atingir o mesmo objetivo de "service sessions" (cada ciclo open/reopen -> resolved como um atendimento), porém adaptado à nossa realidade atual e regras do fork.

## Objective

Entregar relatórios de atendimentos por sessão/ciclo com:

1. API dedicada de relatórios de sessões
2. UI no Dashboard (Reports -> Service Sessions)
3. métricas coerentes com ciclo de atendimento (não lifetime da conversa)
4. rollout seguro por fases, sem regressão para caixas com toggle OFF

## Scope and Non-Goals

### In Scope

- Endpoints de relatório por sessão:
  - `summary`
  - `open`
  - `closed`
  - `by_agent`
  - `by_inbox`
  - `by_team`
  - `by_label`
- filtros por data, business_hours, inbox, team, user_ids e label_ids
- UI com abas e filtros
- i18n apenas em:
  - `en`
  - `pt_BR`

### Out of Scope (Phase 1)

- qualquer tradução fora de `en` e `pt_BR`
- alteração de política de SLA para reopened threads
- unificar Twitter/Email com estratégia genérica de resolver
- mudanças de contratos públicos já existentes em outros relatórios

## Project Rules Applied

- Seguir estratégia de fork: priorizar `custom/` para lógica Ruby.
- Evitar editar arquivos upstream; quando inevitável, marcar com `# FORK:` (Ruby) e `// FORK:` (TS/Vue).
- Não criar setting global; manter escopo por inbox/channel.
- Compatibilidade com Enterprise deve ser preservada.
- Sem documentação extra fora deste plano (este arquivo é a fonte).

## Current State (Relevant)

- Implementação completa em `custom/` (builders + controller) e frontend em `app/javascript/dashboard/`.
- Base de eventos e ajustes por ciclo do plano `conversation-single-history-per-channel` alimentam os `reporting_events`.
- `reporting_events` possui eventos necessários (`conversation_opened`, `conversation_resolved`, `first_response`).
- Semântica de ciclo para inboxes com `lock_to_single_conversation = true` vem de `Custom::ReportingEventListener` e `Custom::Conversations::ResolutionCycle`.
- Índices de período em `reporting_events` via migration `20260226124500_add_period_indexes_to_reporting_events_for_service_sessions.rb`.
- i18n principal em `en/report.json` e `pt_BR/report.json`; label do sidebar em `settings.json`.

## Product/Behavior Decisions

1. **Session definition**
   - Sessão = ciclo entre abertura (ou reabertura) e resolução.
2. **Toggle behavior**
   - Inbox com `lock_to_single_conversation = false`: manter comportamento legado.
   - Inbox com `lock_to_single_conversation = true`: cálculos por ciclo ativos.
3. **Open sessions view**
   - Exibir conversas `open` e `pending`.
4. **Date filter**
   - Sessões fechadas: usar `reporting_events.event_end_time`.
   - Sessões abertas: usar início do ciclo (`conversation_opened.event_end_time` ou `created_at`).
5. **I18n**
   - Somente `en` e `pt_BR`.

## Architecture (Adapted to Our Fork)

### Backend

- Controller de API em `custom/app/controllers/api/v2/accounts/service_session_reports_controller.rb`.
- Builders de relatório em `custom/app/builders/v2/reports/service_sessions/`:
  - `base_builder.rb`
  - `metrics_helper.rb` (percentis e aging de backlog)
  - `summary_builder.rb`
  - `open_sessions_builder.rb`
  - `closed_sessions_builder.rb`
  - `agent_builder.rb`
  - `inbox_builder.rb`
  - `team_builder.rb` (inclui linha para sessões sem time, `id: 0`)
  - `label_builder.rb`
- Rotas em `config/routes.rb` com `# FORK:`.

Decisão técnica:
- manter cálculos baseados em `reporting_events` para sessões fechadas;
- para sessões abertas, usar dados de `conversations` com filtros consistentes.

### Frontend

- API client: `app/javascript/dashboard/api/serviceSessionReports.js`
- Página: `app/javascript/dashboard/routes/dashboard/settings/reports/ServiceSessionReportsIndex.vue`
- Filtros de entidade: `components/ServiceSessionEntityFilter.vue` (inbox, team, agent, label + query params)
- Rota de frontend em `reports.routes.js` (`// FORK:`)
- Item no menu de Reports em `Sidebar.vue` (`// FORK:`)
- Paginação nas abas Open/Closed via `PaginationFooter`
- i18n:
  - `app/javascript/dashboard/i18n/locale/en/report.json`
  - `app/javascript/dashboard/i18n/locale/pt_BR/report.json`
  - sidebar: `en/settings.json` e `pt_BR/settings.json`

## Data Model Decision: `current_session_opened_at`

Temos duas opções:

1. **Sem nova coluna (preferido na Phase 1)**  
   Usar `conversation_opened` + `reporting_events.event_start_time` como fonte de verdade para sessão.
2. **Com nova coluna**  
   Adicionar `conversations.current_session_opened_at` para facilitar open sessions e ordenação.

### Decisão proposta

Começar sem migração para reduzir risco e esforço.  
Se houver necessidade de performance/clareza na listagem de abertas, abrir Phase 2.5 com migração isolada.

## Implementation Phases

### Phase 0 - Alignment and Contracts

Goal: fechar contratos de API e semântica dos filtros.

Tasks:

- [x] confirmar payload/shape de cada endpoint
- [x] confirmar defaults (`since`, `until`, `business_hours`)
- [x] confirmar política de acesso/autorização
- [x] confirmar se menu entra nesta entrega ou feature flag de UI (usa `FEATURE_FLAGS.REPORTS` na rota; sem flag dedicada)

Deliverables:

- contrato final dos endpoints
- critérios de aceite por aba do relatório

### Phase 1 - Backend Report Builders

Goal: criar base de cálculo de sessões sem UI.

Tasks:

- [x] criar `BaseBuilder` com:
  - [x] filtros comuns (`since`, `until`, `business_hours`, `inbox_id`, `team_id`, `user_ids`, `label_ids`)
  - [x] scopes para sessões fechadas (`reporting_events`)
  - [x] scopes para sessões abertas (`conversations`)
- [x] implementar `SummaryBuilder`
- [x] implementar `OpenSessionsBuilder`
- [x] implementar `ClosedSessionsBuilder`
- [x] implementar agrupamentos:
  - [x] `AgentBuilder`
  - [x] `InboxBuilder`
  - [x] `TeamBuilder`
  - [x] `LabelBuilder`
- [x] garantir consistência de ordenação:
  - [x] abertas por atividade recente
  - [x] fechadas por `event_end_time DESC`

Deliverables:

- builders em `custom/app/builders/v2/reports/service_sessions/*`
- cálculo por sessão alinhado ao comportamento de ciclo

### Phase 2 - API Endpoints

Goal: expor os relatórios via API v2.

Tasks:

- [x] adicionar controller de relatório em v2 accounts
- [x] implementar actions:
  - [x] `summary`
  - [x] `open`
  - [x] `closed`
  - [x] `by_agent`
  - [x] `by_inbox`
  - [x] `by_team`
  - [x] `by_label`
- [x] adicionar rotas (`config/routes.rb`) com marcação `# FORK:`
- [x] padronizar resposta JSON (incluindo `total_count` nas listas)
- [x] validar autorização para relatórios

Deliverables:

- endpoints funcionais em `/api/v2/accounts/:account_id/service_session_reports/*`

### Phase 3 - Frontend (Reports UI)

Goal: disponibilizar consumo no Dashboard.

Tasks:

- [x] criar `serviceSessionReports.js` com métodos de API
- [x] criar `ServiceSessionReportsIndex.vue` com abas:
  - [x] Summary
  - [x] Open
  - [x] Closed
  - [x] By Agent
  - [x] By Inbox
  - [x] By Team
  - [x] By Label
- [x] adicionar filtros e sincronização de query params (datas via `ReportFilters`; entidades via `ServiceSessionEntityFilter`)
- [x] adicionar paginação na UI (Open/Closed)
- [x] adicionar rota em `reports.routes.js`
- [x] adicionar item de menu (se aprovado para release)

Deliverables:

- tela funcional de relatórios de sessões

### Phase 4 - i18n (EN + PT_BR only)

Goal: garantir textos completos nos dois idiomas-alvo.

Tasks:

- [x] adicionar chaves `SERVICE_SESSION_REPORTS.*` em `en/report.json`
- [x] adicionar chaves equivalentes em `pt_BR/report.json`
- [x] remover strings hardcoded na UI
- [x] revisar mensagens de erro/estado vazio/loading

Deliverables:

- cobertura i18n completa para `en` e `pt_BR`

### Phase 5 - Validation and Rollout

Goal: liberar com segurança.

Tasks:

- [ ] validar com dados reais em staging
- [x] comparar consistência entre:
  - [x] métricas existentes de reporting_events
  - [x] métricas novas de service sessions
- [x] rodar smoke manual por endpoint + UI
- [ ] confirmar operação com `lock_to_single_conversation` ON e OFF
- [ ] checklist de Go/No-Go

Deliverables:

- aprovação para rollout controlado

### Phase 6 - Hardening (Performance + Reliability)

Goal: preparar a feature para escala de dados com menor risco operacional.

Tasks:

- [x] adicionar paginação nos endpoints de listas:
  - [x] `open` com `page/per_page` (default e limite máximo)
  - [x] `closed` com `page/per_page` (default e limite máximo)
  - [x] incluir metadados de paginação no payload (`page`, `per_page`, `total_count`)
- [x] otimizar índices de `reporting_events` para consultas de relatório por período:
  - [x] avaliar `[:account_id, :name, :event_end_time]`
  - [x] avaliar `[:account_id, :inbox_id, :name, :event_end_time]`
  - [x] migration aplicada (`20260226124500_add_period_indexes_to_reporting_events_for_service_sessions.rb`)
  - [ ] validar plano de execução das queries principais após índice em staging
- [x] escopar subquery de aging por `account_id` em `metrics_helper.rb`
- [x] eliminar risco de N+1 no agrupamento por agente:
  - [x] aplicar eager loading (`includes(:user)`) para `account_users`
- [x] impor limite de janela de datas no controller:
  - [x] definir limite máximo (ex: 90/180 dias) para requests sem agregação pesada
  - [x] retornar erro padronizado quando range exceder o permitido
- [x] revisar semântica de `session_started_at` para sessões abertas:
  - [x] confirmar regra de negócio (início da sessão vs última atividade)
  - [x] alinhar payload backend + renderização frontend ao contrato final

Deliverables:

- endpoints com paginação e metadados
- consultas de relatório com melhor plano de execução
- redução de risco de timeout/N+1 em contas grandes
- contrato de datas e `session_started_at` explicitamente estável

### Phase 8 - Quality and UX Hardening

Goal: specs mínimos, clarificações de UI, export e polish.

Tasks:

- [x] specs mínimos:
  - [x] `spec/custom/builders/v2/reports/service_sessions/summary_builder_spec.rb`
  - [x] `spec/custom/controllers/api/v2/accounts/service_session_reports_controller_spec.rb`
- [x] hint de `total_sessions` no Summary (en + pt_BR)
- [x] alinhar filtro de data de sessões abertas com início do ciclo (`apply_open_date_filter` + `open_cycle_join_sql`)
- [x] sync de `page` na URL para abas Open/Closed (`reportFilterHelper.js` + `ServiceSessionReportsIndex.vue`)
- [x] export CSV client-side para abas de lista e agrupamento (MVP: dados carregados na aba atual)
- [x] fix ESLint i18n em `ServiceSessionEntityFilter.vue` (mapping estático de placeholders)
- [ ] feature flag dedicada para sidebar (skipped: rota já gated por `FEATURE_FLAGS.REPORTS`)
- [ ] AgentBuilder filter rows > 0 (skipped: mantém paridade com `AgentSummaryBuilder`; ver Notes)

Deliverables:

- cobertura de teste smoke para summary builder e controller
- UX de paginação, export e métricas mais claras

### Phase 7 - Advanced Operational Metrics

Goal: ampliar a visão operacional com métricas de qualidade de resolução e risco de backlog.

Tasks:

- [x] adicionar métricas avançadas no `summary`:
  - [x] `reopen_rate` (sessões reabertas / sessões fechadas no período)
  - [x] `p95_first_response_time` (percentil 95)
  - [x] `p95_session_resolution_time` (percentil 95)
- [x] adicionar bloco de envelhecimento de backlog (sessões abertas):
  - [x] `open_sessions_avg_age_seconds`
  - [x] `open_sessions_p95_age_seconds`
  - [x] buckets de aging (`over_24h`, `over_72h`, `over_7d`)
- [x] alinhar contrato de API para novos campos e fallbacks sem quebra de compatibilidade
- [x] exibir as novas métricas na UI de Summary com i18n `en` e `pt_BR`
- [ ] validar consistência em staging com janela curta e longa (`since/until`)

Metric definitions:

- **reopen_rate**
  - numerador: total de eventos `conversation_opened` que iniciam novo ciclo após resolução no período
  - denominador: total de sessões fechadas no período
  - regra: se denominador for zero, retornar `0.0`
- **p95_first_response_time**
  - fonte: durações por ciclo de `first_response`
  - regra: calcular percentil 95 em segundos no período filtrado
- **p95_session_resolution_time**
  - fonte: duração entre abertura do ciclo e `conversation_resolved` por sessão fechada
  - regra: calcular percentil 95 em segundos
- **backlog aging**
  - fonte: sessões abertas no momento da consulta
  - idade: `now - session_started_at`
  - buckets padrão: `>24h`, `>72h`, `>7d`

Deliverables:

- summary com indicadores de cauda (P95) e qualidade (reopen rate)
- visibilidade de risco operacional via aging de backlog
- contrato de métricas avançadas estável para evolução futura

Implementation breakdown (Phase 7):

### Backend file map (Phase 7)

- `custom/app/builders/v2/reports/service_sessions/summary_builder.rb`
  - calcular e retornar:
    - `reopen_rate`
    - `p95_first_response_time`
    - `p95_session_resolution_time`
    - `open_sessions_avg_age_seconds`
    - `open_sessions_p95_age_seconds`
    - `open_sessions_aging_buckets` (`over_24h`, `over_72h`, `over_7d`)
- `custom/app/builders/v2/reports/service_sessions/base_builder.rb`
  - centralizar helpers de percentil e idade de sessão aberta para reuso
  - garantir reaproveitamento dos filtros atuais (`since/until`, `business_hours`, `inbox/team/user/label`)
- `custom/app/controllers/api/v2/accounts/service_session_reports_controller.rb`
  - manter contrato backward compatible para `summary`
  - validar serialização estável dos novos campos numéricos

### Frontend file map (Phase 7)

- `app/javascript/dashboard/routes/dashboard/settings/reports/ServiceSessionReportsIndex.vue`
  - exibir os novos indicadores no bloco de Summary
  - manter fallback visual para valores sem amostra (`NOT_AVAILABLE`)
- `app/javascript/dashboard/i18n/locale/en/report.json`
  - adicionar labels das novas métricas (Summary)
- `app/javascript/dashboard/i18n/locale/pt_BR/report.json`
  - adicionar labels equivalentes em pt_BR

### API payload additions (Phase 7)

`GET /api/v2/accounts/:account_id/service_session_reports/summary`

- novos campos planejados no payload:
  - `reopen_rate` (float)
  - `p95_first_response_time` (integer, seconds)
  - `p95_session_resolution_time` (integer, seconds)
  - `open_sessions_avg_age_seconds` (integer)
  - `open_sessions_p95_age_seconds` (integer)
  - `open_sessions_aging_buckets` (object):
    - `over_24h` (integer)
    - `over_72h` (integer)
    - `over_7d` (integer)

### Suggested execution order (Phase 7)

1. Backend: cálculo + payload no `summary_builder`
2. API contract: validação manual com `curl` (envelope + tipos)
3. Frontend: render dos cards no Summary
4. i18n: `en` e `pt_BR`
5. Staging: comparação janela curta/larga + ON/OFF sem regressão

## File Change Map (Planned)

### Backend

- `custom/app/builders/v2/reports/service_sessions/base_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/metrics_helper.rb`
- `custom/app/builders/v2/reports/service_sessions/summary_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/open_sessions_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/closed_sessions_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/agent_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/inbox_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/team_builder.rb`
- `custom/app/builders/v2/reports/service_sessions/label_builder.rb`
- `custom/app/controllers/api/v2/accounts/service_session_reports_controller.rb`
- `config/routes.rb` (`# FORK:`)
- `db/migrate/20260226124500_add_period_indexes_to_reporting_events_for_service_sessions.rb`

### Frontend

- `app/javascript/dashboard/api/serviceSessionReports.js`
- `app/javascript/dashboard/routes/dashboard/settings/reports/ServiceSessionReportsIndex.vue`
- `app/javascript/dashboard/routes/dashboard/settings/reports/components/ServiceSessionEntityFilter.vue`
- `app/javascript/dashboard/routes/dashboard/settings/reports/helpers/reportFilterHelper.js` (`// FORK:` entity URL helpers)
- `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js` (`// FORK:`)
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (`// FORK:`)
- `app/javascript/dashboard/i18n/locale/en/report.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/report.json`
- `app/javascript/dashboard/i18n/locale/en/settings.json` (sidebar label)
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` (sidebar label)

## API Contract Draft

Base path:

- `GET /api/v2/accounts/:account_id/service_session_reports/summary`
- `GET /api/v2/accounts/:account_id/service_session_reports/open`
- `GET /api/v2/accounts/:account_id/service_session_reports/closed`
- `GET /api/v2/accounts/:account_id/service_session_reports/by_agent`
- `GET /api/v2/accounts/:account_id/service_session_reports/by_inbox`
- `GET /api/v2/accounts/:account_id/service_session_reports/by_team`
- `GET /api/v2/accounts/:account_id/service_session_reports/by_label`

Query params:

- `since` (unix timestamp, optional)
- `until` (unix timestamp, optional)
- `business_hours` (`true`/`false`, optional)
- `inbox_id` (optional)
- `team_id` (optional)
- `user_ids` (csv, optional)
- `label_ids` (csv, optional)
- `page` (integer, optional; default `1`)
- `per_page` (integer, optional; default `25`, max `100`)

## Risks and Mitigations

1. **Métrica divergente entre relatórios antigos e novos**
   - Mitigação: validar lado a lado por janela fixa de datas.
2. **Custo de query em `reporting_events`/joins de label**
   - Mitigação: usar scopes enxutos, paginação, e validar plano SQL.
3. **Inconsistência de sessão aberta**
   - Mitigação: alinhar regra de `session_started_at` desde o contrato.
4. **Mudança de UX em Reports**
   - Mitigação: rollout com feature flag de menu, se necessário.
5. **Conflito em merges upstream**
   - Mitigação: isolar lógica em `custom/` e marcar todo ponto de divergência com `FORK:`.

## Acceptance Criteria

- [x] Endpoints retornam dados consistentes por sessão/ciclo
- [x] Filtros funcionam em todas as abas
- [x] `business_hours=true` altera somente métricas horárias
- [x] UI exibe resumo + listas + agrupamentos
- [x] i18n completo apenas em `en` e `pt_BR`
- [ ] comportamento com toggle ON/OFF validado
- [x] `open/closed` retornam paginação consistente sem degradação
- [x] paginação exposta na UI (Open/Closed)
- [x] endpoint rejeita ranges fora do limite com erro esperado (6 meses, alinhado a `summary_reports`)
- [x] specs mínimos (summary builder + controller smoke)
- [x] hint de `total_sessions` na UI
- [x] export CSV client-side (open/closed/grouped)
- [x] paginação Open/Closed sincronizada com query param `page`
- [x] sem N+1 no agrupamento por agente (`includes(:user)`)
- [x] filtros de entidade (inbox/team/agent/label) na UI e API
- [ ] queries principais de relatório usam índices adequados em staging
- [ ] métricas avançadas (reopen rate, p95, backlog aging) validadas em staging

## Definition of Done

- [ ] Fases 0 a 7 concluídas
- [ ] validação funcional concluída em staging
- [ ] sem regressão dos relatórios atuais
- [ ] documentação deste plano atualizada com status final
- [ ] hardening de performance/confiabilidade validado em staging

## Staging Validation Checklist (Phase 5)

Use este bloco como guia de execução e evidência para fechar o plano.

### 1) Pré-condições

- [ ] Ambiente de staging atualizado com branch atual
- [ ] Migration aplicada com sucesso (`db:migrate`)
- [ ] Dados mínimos disponíveis para relatórios (conversations + reporting_events)
- [ ] Pelo menos 1 inbox com `lock_to_single_conversation = true`
- [ ] Pelo menos 1 inbox com `lock_to_single_conversation = false`

### 2) Smoke API (endpoints)

Validar status `200` e payload não quebrado para:

- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/summary`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/open`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/closed`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/by_agent`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/by_inbox`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/by_team`
- [ ] `GET /api/v2/accounts/:account_id/service_session_reports/by_label`

### 3) Filtros e consistência

- [ ] `since/until` aplicam corretamente (janela curta vs longa)
- [ ] `business_hours=true` altera apenas métricas horárias
- [ ] `inbox_id` filtra corretamente
- [ ] `team_id` filtra corretamente
- [ ] `user_ids` filtra corretamente
- [ ] `label_ids` filtra corretamente

### 4) Toggle ON/OFF (critério pendente principal)

- [ ] Inbox ON (`lock_to_single_conversation=true`): sessões por ciclo coerentes com `conversation_opened`/`conversation_resolved`
- [ ] Inbox OFF (`lock_to_single_conversation=false`): comportamento legado preservado
- [ ] Comparativo ON vs OFF sem regressão funcional

### 5) UI (Dashboard)

- [ ] Rota acessível: Reports -> Service Sessions
- [ ] Abas funcionais: Summary, Open, Closed, By Agent, By Inbox, By Team, By Label
- [ ] Loading/error/empty state renderizam corretamente
- [ ] i18n correto em `en` e `pt_BR` (sem string hardcoded)

### 6) Regressão básica

- [ ] Relatórios existentes continuam funcionando (overview/conversation/agent/inbox/team/label/csat/sla/bot)
- [ ] Sem erro novo no backend logs para requests de reports
- [ ] Sem erro novo no frontend console para tela de service sessions

### 7) Go/No-Go

- [ ] GO: todos os itens críticos acima validados
- [ ] NO-GO: rollback planejado/documentado caso haja inconsistência
- [ ] Decisão registrada (data, responsável, observações)

### 8) Fechamento do plano

Após validação staging:

- [ ] Marcar `comportamento com toggle ON/OFF validado`
- [ ] Marcar todos itens de `Definition of Done`
- [ ] Atualizar este documento com status final da feature

## ON/OFF Validation Runbook (Staging)

Use este runbook como suporte operacional para executar os itens do
`Staging Validation Checklist (Phase 5)` acima (sem duplicar marcação de checklist).

### Inputs

- `ACCOUNT_ID`: conta em staging
- `INBOX_ON_ID`: inbox com `lock_to_single_conversation = true`
- `INBOX_OFF_ID`: inbox com `lock_to_single_conversation = false`
- `SINCE`: unix timestamp (início)
- `UNTIL`: unix timestamp (fim)
- `TOKEN`: access token com permissão de relatório
- `BASE_URL`: URL staging (ex: `https://staging.example.com`)

### 1) Verificar setup ON/OFF

```bash
bundle exec rails runner "
account = Account.find(ENV.fetch('ACCOUNT_ID'))
on_inbox = account.inboxes.find(ENV.fetch('INBOX_ON_ID'))
off_inbox = account.inboxes.find(ENV.fetch('INBOX_OFF_ID'))
puts \"ON inbox lock_to_single_conversation=#{on_inbox.lock_to_single_conversation}\"
puts \"OFF inbox lock_to_single_conversation=#{off_inbox.lock_to_single_conversation}\"
"
```

Esperado:
- ON inbox => `true`
- OFF inbox => `false`

### 2) Validar summary por inbox (API)

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/summary?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID&business_hours=false"

curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/summary?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_OFF_ID&business_hours=false"
```

Esperado:
- resposta `200` nos dois casos
- payload com:
  - `open_sessions_count`
  - `closed_sessions_count`
  - `total_sessions`
  - `avg_session_duration`
  - `avg_first_response_time`

### 3) Validar endpoints principais ON/OFF

Executar para `INBOX_ON_ID` e repetir para `INBOX_OFF_ID`:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/open?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID"

curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/closed?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID"

curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/by_agent?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID"
```

Esperado:
- respostas `200`
- `open/closed` retornam `{ sessions, total_count }`
- agrupamentos retornam lista por entidade sem erro

### 4) Validar `business_hours=true`

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/summary?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID&business_hours=true"

curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/summary?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID&business_hours=false"
```

Esperado:
- sem erro de endpoint
- métricas de tempo podem diferir entre `true` e `false`
- contadores (open/closed/total) permanecem coerentes

### 5) Validar UI (Reports -> Service Sessions)

Executar manualmente na UI:

- abrir rota de reports service sessions
- alternar abas (Summary/Open/Closed/By Agent/By Inbox/By Team/By Label)
- aplicar filtro de datas e business hours
- validar empty state sem dados
- validar i18n em `en` e `pt_BR`

### 6) Critério de fechamento ON/OFF

Marcar como concluído quando:

- API e UI funcionam para inbox ON e OFF
- sem erro no backend log para requests da feature
- sem regressão visível em relatórios existentes

Então atualizar:

- `comportamento com toggle ON/OFF validado`
- `Fases 0 a 5 concluídas`
- `validação funcional concluída em staging`
- `sem regressão dos relatórios atuais`

## Suggested Execution Order (Practical)

1. Phase 0
2. Phase 1 + 2 (backend completo)
3. Smoke API
4. Phase 3 + 4 (UI + i18n)
5. Phase 5 (validação e rollout)
6. Phase 6 (hardening de performance/confiabilidade)
7. Phase 7 (métricas operacionais avançadas)
8. Phase 8 (specs, UX polish, export CSV)

---

## Notes

- Este plano é deliberadamente incremental para reduzir risco.
- `total_sessions` no summary soma snapshot de abertos + fechados no período; não é um total estritamente comparável.
- Sessões abertas: filtro de data usa início do ciclo (`conversation_opened` ou `created_at`); `session_started_at` e aging usam a mesma regra.
- Menu/rota gated por `FEATURE_FLAGS.REPORTS` (sem flag dedicada de service sessions).
- `AgentBuilder` lista todos os agentes da conta (paridade com `AgentSummaryBuilder`); filtrar zeros exigiria decisão de produto.
- Comportamento por ciclo depende de `lock_to_single_conversation` nos listeners custom; a API não bifurca por toggle — use filtro de inbox para comparar ON/OFF.
- Se performance de sessões abertas ficar limitada sem `current_session_opened_at`, abrir fase adicional específica para migração de schema, separada desta entrega principal.
