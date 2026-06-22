# Status da documentação — WhatsApp providers (fork)

Revisão consolidada **jun/2026**. Atualizar este arquivo ao fechar fases de código.

**Escopo:** `doc/feature/whatsapp-provider/` + código `custom/` relacionado.

---

## Resumo por provider

| Provider key | Gateway | Doc | Código `custom/` | Spike/fixtures | Próximo passo |
|--------------|---------|-----|------------------|----------------|---------------|
| `evolution` | Evolution API Node/Baileys | ✅ 18 arquivos | ✅ Fase 0–4 parcial (~95%) | ✅ T0 REST + Playwright E2E | Credenciais E2E em CI/staging |
| `evolution_go` | Evolution Go/whatsmeow | ✅ consolidada | ❌ não iniciado | ⚠️ E2E pendente | Fase 0 → Fase 1 |
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
| Wizard + settings Vue | `Evolution.vue`, `EvolutionQrScanModal`, `EvolutionSettingsPage.vue`, … | ✅ |
| Specs `spec/custom/` + Playwright | normalizer, controller, job, connection, import | ✅ ~42 + 5 E2E |

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
| Código alinhado | ✅ ~95% | E2E Playwright parcial; wizard QR via modal |
| Fixtures | ✅ T0 | `spec/fixtures/evolution/` |

Índice: [evolution-api/README.md](./evolution-api/README.md) · Tarefas: [tasks.md](./evolution-api/tasks.md)

---

## Evolution Go (`evolution-go/`)

| Área | Score | Gap principal |
|------|-------|---------------|
| Planejamento + ADRs §1–26 | ✅ | — |
| Contratos + wizard + composable | ✅ | — |
| Integração (escopo fork) | ✅ | Sem provisionar Evolution Go |
| E2E com instância operador | ⚠️ | Fixtures reais + versão |
| Fase 2 paths (settings, mídia) | ⚠️ | advanced-settings body, download |
| Código | ❌ | Fase 0 não iniciada |

Índice: [evolution-go/README.md](./evolution-go/README.md) · Status: [status.md](./evolution-go/status.md) · Tarefas: [tasks.md](./evolution-go/tasks.md)

---

## Inconsistências corrigidas nesta revisão

| Item | Correção |
|------|----------|
| `gaps-and-blockers` citava `PROVIDERS` sem `evolution` | Atualizado — evolution implementado |
| `architecture-current-whatsapp` só mostrava upstream | Seção fork overlay adicionada |
| `evolution-go/README` duplicava Brand assets | Removido |
| `evolution-go/README` "Evolution planejada" | Corrigido — Node já em `custom/` |
| Evolution Go doc consolidada | Integração only — sem spike local |
| `evolution-api/README` tabela ConnectionService | Linha corrigida |
| Parent README sem status código | Tabela + link STATUS |
| `PROVIDERS` exemplo inclui `evolution_go` antes do código | Nota: só `evolution` no repo hoje |

---

## Ordem de trabalho recomendada

```
1. Evolution Node — fechar E2E (validation-checklist §2–4)
2. Evolution Go — Fase 0 → Fase 1 (E2E em paralelo)
3. Demais gateways (Z-API, NotificaMe) — após padrão estável
```

---

## Manutenção

| Provider | Script |
|----------|--------|
| Evolution API | `./evolution-api/sync-documentation-links.sh` |
| Evolution Go | `./evolution-go/sync-documentation-links.sh` |

Atualizar **STATUS.md** + README do provider ao fechar cada fase.
