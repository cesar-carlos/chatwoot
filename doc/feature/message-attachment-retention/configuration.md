# Configuração — retenção de anexos

## Variáveis de ambiente

Documentadas em [`.env.example`](../../../.env.example):

```bash
MESSAGE_ATTACHMENT_RETENTION_ENABLED=true
MESSAGE_ATTACHMENT_RETENTION_DAYS=90
MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS=1
```

| Variável | Default (fork) | Descrição |
|----------|----------------|-----------|
| `MESSAGE_ATTACHMENT_RETENTION_ENABLED` | `false` (código) / `true` (.env desta instalação) | Liga ou desliga a feature |
| `MESSAGE_ATTACHMENT_RETENTION_DAYS` | `90` | Idade máxima do anexo em dias |
| `MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS` | `1` | `1` = todas as contas diariamente; `7` = 1/7 por dia |
| `MESSAGE_ATTACHMENT_RETENTION_MAX_PURGE_PER_RUN` | `2000` | Máximo de anexos apagados por execução do job |
| `MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS` | `100` | Limite de re-enfileiramentos quando ainda há backlog |
| `MESSAGE_ATTACHMENT_RETENTION_DRY_RUN` | `false` | Simula purge sem `destroy!`; grava eventos `dry_run`; não re-enfileira por backlog |
| `MESSAGE_ATTACHMENT_RETENTION_MAX_FAILURE_ATTEMPTS` | `3` | Quarentena após N falhas consecutivas no mesmo anexo |
| `MESSAGE_ATTACHMENT_RETENTION_AUDIT_RETENTION_DAYS` | `365` | Eventos de auditoria mais antigos são removidos diariamente |

A feature só fica ativa quando **ambas** as condições são verdadeiras:

1. `ENABLED` é truthy
2. `DAYS` é um inteiro positivo

### Janela efetiva de retenção

Com `DISTRIBUTION_GROUPS=1` (padrão deste fork), o cutoff de **90 dias** é aplicado diariamente — sem slack adicional por rotação semanal.

Com `DISTRIBUTION_GROUPS=7`, a idade efetiva máxima aproximada é **`DAYS + (N - 1)`** dias.

## Prioridade de configuração

| Chave | Ordem de leitura |
|-------|------------------|
| `ENABLED` | **ENV** (se chave existe) → `InstallationConfig` → `false` (código) |
| `DAYS` | **ENV** (se chave existe) → `InstallationConfig` → `90` |
| `DRY_RUN` | **ENV** (se chave existe) → `InstallationConfig` → `false` |
| Demais | **ENV** → constante no código |

O initializer semeia `DAYS=90`, `ENABLED=false` e `DRY_RUN=false` se ausentes no banco.

## Mutex por conta

`PurgeAccountAttachmentsJob` adquire lock Redis `RETENTION_PURGE_MUTEX::<account_id>` (TTL 30 min). Jobs concorrentes na mesma conta são descartados após 3 tentativas com log `lock_skipped`.

## Reinício necessário

Alterações em ENV exigem restart dos processos Rails/Sidekiq.

## Verificação manual

```ruby
Custom::Retention::Policy.enabled?
Custom::Retention::Policy.dry_run?
Custom::Retention::Policy.retention_days
Custom::Retention::Policy.max_failure_attempts

# Dry-run seguro
ENV['MESSAGE_ATTACHMENT_RETENTION_DRY_RUN'] = 'true'
Custom::Retention::SchedulerJob.perform_now

Custom::Retention::PurgeMessageAttachmentsService.new(account: Account.first).perform
# => { deleted_count:, has_more:, failed_count:, bytes_freed: }

AttachmentRetentionEvent.where(account_id: 1).order(created_at: :desc).limit(10)
AttachmentRetentionEvent.where(run_id: 'uuid').count
```

## Logs (auditoria operacional)

Logs estruturados em JSON. Filtrar por `component`:

| Componente | Eventos |
|------------|---------|
| `Custom::Retention::PurgeMessageAttachmentsService` | `start`, `completed`, `purge_failed`, `attachment_quarantined`, `message_update_failed`, `reindex_failed`, `audit_record_failed` |
| `Custom::Retention::SchedulerJob` | `completed` (inclui `accounts_skipped`, `cutoff`) |
| `Custom::Retention::PurgeRetentionAuditEventsJob` | `completed` |
| `Custom::Retention::PurgeAccountAttachmentsJob` | `lock_skipped` |
| `Custom::Retention::OperationalAlert` | `reenqueue_limit_reached` (+ Sentry warning se `SENTRY_DSN` configurado) |

## Auditoria persistente (LGPD)

Tabela `attachment_retention_events` — status: `purged`, `dry_run`, `failed`, `skipped_quarantine`.

Consulta típica:

```ruby
AttachmentRetentionEvent.where(account_id: account.id, status: 'purged')
  .where('created_at >= ?', 7.days.ago)
```

Falhas repetidas ficam em `attachment_retention_failures` até purge bem-sucedido ou intervenção manual (apagar a linha da quarentena).

Eventos de auditoria sobrevivem à exclusão de conta (`account_id` anulado). Falhas de quarentena são removidas com a conta.
