# Retenção de anexos de mensagens

Política de tempo de vida para anexos de conversa (`Attachment` + Active Storage ou `external_url`). Implementação no overlay `custom/` do fork — não altera upstream.

**Escopo atual:** anexos de mensagem com blob local (`has_one_attached :file`) **ou** somente `external_url`.

**Padrão desta instalação:** retenção **ativa** por **90 dias**, com purge **diário** em todas as contas (`DISTRIBUTION_GROUPS=1`).

**Fora do escopo:** documentos Captain, gravações de chamada, avatares, macros, purge de blobs órfãos, TTL por conta, UI de auditoria.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| Operador / DevOps (ativar, configurar) | [configuration.md](./configuration.md) |
| Desenvolvedor (arquitetura, código, jobs) | [implementation.md](./implementation.md) |

---

## Rollout recomendado

1. Ativar com `MESSAGE_ATTACHMENT_RETENTION_DRY_RUN=true` e `ENABLED=true`
2. Rodar `SchedulerJob` ou aguardar o ciclo diário; inspecionar `attachment_retention_events` (`status: dry_run`)
3. Desligar dry-run (`DRY_RUN=false`); monitorar logs e Sentry (`reenqueue_limit_reached`)
4. Consultar auditoria: `AttachmentRetentionEvent.where(account_id: N).order(created_at: :desc)`

---

## Comportamento resumido

| Estado | Efeito |
|--------|--------|
| Desligado (`ENABLED=false`) | Nenhum purge é agendado |
| Ligado + `DAYS > 0` | Diariamente, anexos elegíveis com `created_at` anterior ao cutoff são removidos |
| `DRY_RUN=true` | Conta candidatos e grava auditoria sem `destroy!` |
| `DAYS` ausente ou ≤ 0 | Tratado como desligado |

- O registro `Attachment` e o blob Active Storage são destruídos (`destroy!`), exceto em dry-run.
- A **mensagem permanece**; o dashboard recebe `send_update_event`; busca avançada reindexa a mensagem.
- Anexos com falhas repetidas entram em quarentena após `MAX_FAILURE_ATTEMPTS`.

---

## Arquivos principais

```
custom/app/services/custom/retention/
  policy.rb
  purge_message_attachments_service.rb
  message_post_purge_service.rb
  record_purge_event_service.rb
  attachment_failure_tracker.rb
  operational_alert.rb
custom/app/jobs/custom/retention/
  scheduler_job.rb
  purge_account_attachments_job.rb
  purge_retention_audit_events_job.rb
custom/app/models/
  attachment_retention_event.rb
  attachment_retention_failure.rb
custom/config/initializers/
  retention_config.rb
```

---

## Configuração padrão (esta instalação)

```bash
MESSAGE_ATTACHMENT_RETENTION_ENABLED=true
MESSAGE_ATTACHMENT_RETENTION_DAYS=90
MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS=1
```

Reinicie processos web e worker (Sidekiq) após alterar. Detalhes em [configuration.md](./configuration.md).
