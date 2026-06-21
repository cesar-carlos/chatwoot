# Status da documentação — WhatsApp providers (fork)

Revisão consolidada **jun/2026**. Atualizar este arquivo ao fechar fases de código ou spikes.

**Escopo:** `doc/feature/whatsapp-provider/` (53 arquivos) + código `custom/` relacionado.

---

## Resumo por provider

| Provider key | Gateway | Doc | Código `custom/` | Spike/fixtures | Próximo passo |
|--------------|---------|-----|------------------|----------------|---------------|
| `evolution` | Evolution API Node/Baileys | ✅ 18 arquivos | ✅ Fase 0–3 (~95%) | ✅ T0 REST + E2E local | Wizard QR com scan real (opcional) |
| `evolution_go` | Evolution Go/whatsmeow | ✅ 25 arquivos (~92%) | ❌ não iniciado | ❌ pendente | Spike Docker P1 |
| `zapi` | Z-API SaaS | ⚠️ só comparação | ❌ | — | Após piloto Evolution |
| `notificame` | NotificaMe | 📁 pasta separada | ❌ | — | [plano-geral](../notificame-whatsapp-integration/plano-geral.md) |

---

## Código fork — o que já existe (`evolution`)

| Componente | Local | Estado |
|------------|-------|--------|
| `PROVIDERS` inclui `evolution` | `app/models/channel/whatsapp.rb` | ✅ `# FORK:` |
| Índice único `instance_name` | migration / schema | ✅ |
| `MessagingProvider::Registry` | `custom/lib/messaging_provider/` | ✅ só `evolution` |
| Prepend `Channel::Whatsapp#provider_service` | `custom/app/models/custom/channel/whatsapp.rb` | ✅ |
| Prepend `WhatsappEventsJob` | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | ✅ |
| Prepend `MessageWindowService` | `custom/.../message_window_service.rb` | ✅ bypass 24h |
| Webhook route | `POST /webhooks/evolution/:instance_name` | ✅ |
| `EvolutionController` | `custom/app/controllers/webhooks/evolution_controller.rb` | ✅ |
| ApiClient, ConnectionService, Normalizer, Service | `custom/app/services/custom/whatsapp/` | ✅ |
| Wizard + settings Vue | `Evolution.vue`, `EvolutionSettingsPage.vue`, … | ✅ |
| Specs `spec/custom/` | normalizer, controller, job, connection | ✅ |

**Ainda não no código:** `evolution_go`, `zapi`, `notificame` em `PROVIDERS`.

---

## Documentação pai (`whatsapp-provider/`)

| Arquivo | Estado | Notas revisão jun/2026 |
|---------|--------|----------------------|
| [README.md](./README.md) | ✅ | Índice + visão; link para este STATUS |
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | ✅ | Atualizado — overlay fork vs upstream |
| [gaps-and-blockers.md](./gaps-and-blockers.md) | ✅ | Mitigações Evolution marcadas implementadas |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | ✅ | Fase 0 parcial; tabela multi-provider |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | ✅ | Inclui Evolution Go |
| [provider-comparison.md](./provider-comparison.md) | ✅ | Tabela Node vs Go |
| [feature-mapping.md](./feature-mapping.md) | ✅ | Links para matrizes por provider |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | ✅ | Sem alteração necessária |

---

## Evolution API (`evolution-api/`)

| Área | Score | Gap principal |
|------|-------|---------------|
| Planejamento + ADRs | ✅ | — |
| API reference + webhooks | ✅ | — |
| Código alinhado | ✅ ~95% | E2E §2–3 local OK; wizard QR scan manual |
| Fixtures | ✅ T0 | `spec/fixtures/evolution/` |

Índice: [evolution-api/README.md](./evolution-api/README.md) · Tarefas: [tasks.md](./evolution-api/tasks.md)

---

## Evolution Go (`evolution-go/`)

| Área | Score | Gap principal |
|------|-------|---------------|
| Planejamento + ADRs §1–23 | ✅ | — |
| Contratos + wizard spec | ✅ | — |
| Spike runtime | ❌ | Fixtures + versão congelada |
| Código | ❌ | Bloqueado por P1 |

Índice: [evolution-go/README.md](./evolution-go/README.md) · Gaps: [gaps-and-improvements.md](./evolution-go/gaps-and-improvements.md) · Tarefas: [tasks.md](./evolution-go/tasks.md)

---

## Inconsistências corrigidas nesta revisão

| Item | Correção |
|------|----------|
| `gaps-and-blockers` citava `PROVIDERS` sem `evolution` | Atualizado — evolution implementado |
| `architecture-current-whatsapp` só mostrava upstream | Seção fork overlay adicionada |
| `evolution-go/README` duplicava Brand assets | Removido |
| `evolution-go/README` "Evolution planejada" | Corrigido — Node já em `custom/` |
| `evolution-api/README` tabela ConnectionService | Linha corrigida |
| Parent README sem status código | Tabela + link STATUS |
| `PROVIDERS` exemplo inclui `evolution_go` antes do código | Nota: só `evolution` no repo hoje |

---

## Ordem de trabalho recomendada

```
1. Evolution Node — fechar E2E (validation-checklist §2–4)
2. Evolution Go — spike P1 → fixtures
3. Evolution Go — Fase 0 (reusar prepends) + Fase 1
4. Demais gateways (Z-API, NotificaMe) — após padrão estável
```

---

## Manutenção

| Provider | Script |
|----------|--------|
| Evolution API | `./evolution-api/sync-documentation-links.sh` |
| Evolution Go | `./evolution-go/sync-documentation-links.sh` |

Atualizar **STATUS.md** + README do provider ao fechar cada fase.
