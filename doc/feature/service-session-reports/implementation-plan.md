# Service Session Reports

Contrato da feature no fork. O código de API, builders, UI e i18n (`en`, `pt_BR`) está implementado. A validação em staging continua aberta.

## O que é uma sessão

Sessão fechada é um evento `conversation_resolved`. A duração gravada nesse evento já nasce do ciclo:

- lock desligado: `Custom::Conversations::ResolutionCycle` usa `conversation.created_at`
- lock ligado: o mais recente entre `created_at`, o último `conversation_opened.event_end_time` e `additional_attributes.evolution_pending_since`

`evolution_pending_since` cobre o ciclo Evolution que começa no primeiro inbound pós-resolve, enquanto a conversa ainda está `pending`. A mesma regra está em `Custom::Conversations::ResolutionCycle`.

Sessão aberta é uma conversa `open` ou `pending`. O relatório calcula o início na hora da query, em `MetricsHelper::OPEN_SESSION_STARTED_AT_SQL`:

- lock desligado: `conversations.created_at`, mesmo que exista `conversation_opened` mais recente
- lock ligado: `GREATEST(created_at, último conversation_opened, evolution_pending_since)`

A API bifurca esse início pelo toggle. Sessões fechadas não recalculam: leem `reporting_events.value` / `value_in_business_hours`.

## Acesso

- `ReportPolicy#view?`: administrador, ou permissão Enterprise `report_manage`
- rota `service-sessions` com `FEATURE_FLAGS.REPORTS` e permissões `administrator`, `report_manage`
- sem feature flag própria
- agente sem `report_manage` recebe 401

## API

Base: `GET /api/v2/accounts/:account_id/service_session_reports`

| Action | Papel |
| --- | --- |
| `summary` | contagens, médias, P95, reopen rate, aging |
| `open` | sessões abertas paginadas |
| `closed` | sessões fechadas paginadas |
| `by_agent` | uma linha por usuário da conta |
| `by_inbox` | uma linha por inbox |
| `by_team` | uma linha por time, mais sem time quando houver |
| `by_label` | uma linha por etiqueta (`name` = `label.title`) |

Query params:

- `since`, `until`: unix timestamp, opcionais
- `business_hours`: `true` / `false`
- `inbox_id`, `team_id`
- `user_ids`, `label_ids`: CSV. A UI envia um único id por tipo
- `page` (default `1`), `per_page` (default `25`, máximo `100`)

Janela: se os dois limites vêm juntos e `since > until`, 422 `errors.reports.invalid_date_range`. Se a diferença passa de `6.months`, 422 `errors.reports.date_range_too_long`. Com só um lado, o outro fica sem teto e o limite de 6 meses não se aplica. O mesmo recorte dos summary reports.

`business_hours=true` troca `value` por `value_in_business_hours` nas médias, nos P95 e em `session_duration` das fechadas. Contagens, `reopen_rate` e aging não mudam.

### Summary

```json
{
  "open_sessions_count": 1,
  "closed_sessions_count": 2,
  "total_sessions": 3,
  "avg_session_duration": 120.0,
  "avg_first_response_time": 30.0,
  "reopen_rate": 0.5,
  "p95_first_response_time": 60,
  "p95_session_resolution_time": 300,
  "open_sessions_avg_age_seconds": 3600,
  "open_sessions_p95_age_seconds": 7200,
  "open_sessions_aging_buckets": { "over_24h": 1, "over_72h": 0, "over_7d": 0 }
}
```

Médias e P95 vêm `null` sem amostra. A UI mostra N/D.

- `open_sessions_count`: abertas cujo início do ciclo cai em `since`/`until`
- `closed_sessions_count`: `conversation_resolved` com `event_end_time` na janela
- `total_sessions`: snapshot de abertas na janela mais fechadas na janela. Não é um total único
- `avg_session_duration` / `p95_session_resolution_time`: duração gravada no `conversation_resolved`
- `avg_first_response_time` / `p95_first_response_time`: eventos `first_response` com `event_end_time` na janela (momento da resposta, não o fechamento). Novo evento por ciclo só existe com o lock ligado, porque `first_reply_created_at` é zerado na reabertura
- `reopen_rate`: `conversation_opened` com `value > 0` e `event_end_time` na janela, dividido pelas fechadas da janela. `value` é o tempo desde a resolução anterior; `0` é a primeira abertura e não entra. Sem fechadas, `0.0`. Arredondado em 4 casas. Pode passar de 1, porque reaberturas e fechamentos não são pareados
- aging: snapshot atual de `open`/`pending`, com os filtros de inbox, time, agente e label, sem janela de datas. Idade = agora menos o mesmo início de ciclo. Buckets `>24h`, `>72h`, `>7d` se acumulam

### Open / closed

```json
{
  "sessions": [],
  "page": 1,
  "per_page": 25,
  "total_count": 0,
  "total_pages": 0
}
```

Abertas ordenam pelo início do ciclo, da mais nova para a mais antiga. `last_activity_at` não entra na ordem nem no filtro. Cada item traz `id` (conversation), `display_id`, `contact`, `assignee`, `inbox`, `team`, `session_started_at`, `status` (`open` ou `pending`), `waiting_since`.

Fechadas ordenam por `event_end_time DESC`. `id` é o reporting event. Também vêm `conversation_id`, `display_id`, contato, assignee, inbox, team, `session_duration` (respeita `business_hours`), `session_duration_business_hours` (sempre o valor em horário comercial), `resolved_at`, `session_started_at` (`event_start_time` gravado na resolução).

### Agrupamentos

Array puro, sem paginação. Cada linha: `id`, `name`, `open_sessions_count`, `closed_sessions_count`, `avg_session_duration`.

Agente, inbox e label incluem entidades zeradas. Time também, e acrescenta `id: 0`, `name: null` só quando existe sessão aberta ou fechada sem time. A UI traduz essa linha como "Sem time".

Abertas agrupam por `assignee_id`, `inbox_id`, `team_id` ou etiqueta da conversa. Fechadas agrupam por `reporting_events.user_id` (assignee no momento do resolve), `inbox_id`, `conversations.team_id` ou etiqueta. O filtro `user_ids` segue a mesma divisão: assignee nas abertas, `user_id` do evento nas fechadas, no first response e no reopen.

## UI

- página `ServiceSessionReportsIndex.vue`, menu Reports → Service Sessions
- abas Summary, Open, Closed, By Agent, By Inbox, By Team, By Label
- datas e business hours em `ReportFilters`; inbox, time, agente e etiqueta em `ServiceSessionEntityFilter` (um valor por tipo, sincronizado na URL)
- `page` na URL só para Open/Closed
- status `open` / `pending` traduzidos (`SERVICE_SESSION_REPORTS.STATUS`)
- CSV client-side da aba carregada. Open/Closed exportam a página atual (25). Agrupamentos exportam a lista inteira. Summary não exporta. Timestamps no CSV ficam em unix

## Arquivos

Backend:

- `custom/app/controllers/api/v2/accounts/service_session_reports_controller.rb` (herda `Api::V1::Accounts::BaseController`)
- `custom/app/builders/v2/reports/service_sessions/` (`base_builder`, `metrics_helper`, `summary`, `open`, `closed`, `agent`, `inbox`, `team`, `label`)
- `config/routes.rb` (`# FORK:`)
- `db/migrate/20260226124500_add_period_indexes_to_reporting_events_for_service_sessions.rb`
- `db/migrate/20261024143000_remove_unused_current_session_opened_at_from_conversations.rb`

Frontend:

- `app/javascript/dashboard/api/serviceSessionReports.js`
- `app/javascript/dashboard/routes/dashboard/settings/reports/ServiceSessionReportsIndex.vue`
- `app/javascript/dashboard/routes/dashboard/settings/reports/components/ServiceSessionEntityFilter.vue`
- `app/javascript/dashboard/routes/dashboard/settings/reports/helpers/reportFilterHelper.js` (`// FORK:`)
- `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js` (`// FORK:`)
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (`// FORK:`)
- i18n `en` e `pt_BR` em `report.json`; label do menu em `settings.json`

## `current_session_opened_at`

A coluna entrou em `schema.rb` num dump de schema sem migration e sem leitor ou escritor. Os relatórios não usam essa coluna. A migration `20261024143000` remove a coluna e o índice quando existem.

Se a listagem de abertas ficar cara, uma coluna de início de ciclo pode voltar numa migration própria. Até lá, a fonte é o SQL de `MetricsHelper`.

## Specs

- `spec/custom/builders/v2/reports/service_sessions/summary_builder_spec.rb` — janela, aging sem data, lock off/on, `evolution_pending_since`, business hours, P95, reopen rate acima de 1
- `spec/custom/builders/v2/reports/service_sessions/open_sessions_builder_spec.rb` — ordem pelo início do ciclo e paginação
- `spec/custom/builders/v2/reports/service_sessions/agent_builder_spec.rb` — assignee versus usuário do evento
- `spec/custom/builders/v2/reports/service_sessions/team_builder_spec.rb` — linha sem time só quando há sessão
- `spec/custom/controllers/api/v2/accounts/service_session_reports_controller_spec.rb` — auth, janela de 6 meses, metadata de `open`

Não há spec de inbox/label builder nem comparação automática com os relatórios antigos.

## Fora deste relatório

- traduções além de `en` e `pt_BR`
- SLA de thread reaberta
- unificar Twitter/Email no resolver
- mudar o contrato dos relatórios já existentes
- flag de menu exclusiva

## Pendente em staging

- [ ] branch e migration `20261024143000` aplicadas
- [ ] `EXPLAIN` das queries principais usa `index_reporting_events_on_account_name_event_end_time` e `index_reporting_events_on_account_inbox_name_event_end_time`
- [ ] smoke 200 de `summary`, `open`, `closed`, `by_agent`, `by_inbox`, `by_team`, `by_label`
- [ ] `since`/`until`, `business_hours`, `inbox_id`, `team_id`, `user_ids`, `label_ids`
- [ ] inbox com lock ligado: início do ciclo coerente com `conversation_opened` e, no Evolution pending, com `evolution_pending_since`
- [ ] inbox com lock desligado: abertas contam a partir de `created_at`
- [ ] UI: abas, loading, vazio, erro, i18n `en` e `pt_BR`, CSV da página atual
- [ ] relatórios existentes sem regressão
- [ ] Go/No-Go registrado (data, responsável, observação)

## Runbook ON/OFF

Inputs: `ACCOUNT_ID`, `INBOX_ON_ID`, `INBOX_OFF_ID`, `SINCE`, `UNTIL`, `TOKEN`, `BASE_URL`.

```bash
bundle exec rails runner "
account = Account.find(ENV.fetch('ACCOUNT_ID'))
on_inbox = account.inboxes.find(ENV.fetch('INBOX_ON_ID'))
off_inbox = account.inboxes.find(ENV.fetch('INBOX_OFF_ID'))
puts \"ON inbox lock_to_single_conversation=#{on_inbox.lock_to_single_conversation}\"
puts \"OFF inbox lock_to_single_conversation=#{off_inbox.lock_to_single_conversation}\"
"
```

Summary por inbox:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/summary?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID&business_hours=false"
```

Esperado no summary: `open_sessions_count`, `closed_sessions_count`, `total_sessions`, `avg_session_duration`, `avg_first_response_time`, `reopen_rate`, `p95_first_response_time`, `p95_session_resolution_time`, `open_sessions_avg_age_seconds`, `open_sessions_p95_age_seconds`, `open_sessions_aging_buckets`.

Open, closed e by_agent, repetir com `INBOX_OFF_ID`:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v2/accounts/$ACCOUNT_ID/service_session_reports/open?since=$SINCE&until=$UNTIL&inbox_id=$INBOX_ON_ID"
```

`open` e `closed` respondem `sessions`, `page`, `per_page`, `total_count`, `total_pages`. Agrupamentos respondem um array.

`business_hours=true` pode mudar médias e P95. Contagens e aging permanecem.

Na UI, alternar as sete abas, datas, business hours, um filtro de entidade, estado vazio e os dois idiomas. CSV de Open/Closed cobre só a página visível.

Fechar o pendente de staging quando API e UI passarem nos dois toggles, sem erro novo de reports no log e sem regressão dos relatórios atuais.
