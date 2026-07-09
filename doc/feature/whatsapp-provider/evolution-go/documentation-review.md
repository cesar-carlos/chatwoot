# Revisão da documentação — Evolution Go (`evolution_go`)

---

## Histórico de revisões

| Data | Escopo |
|------|--------|
| 24/jun/2026 | Revisão inicial — comparação cruzada com código Evolution Node implementado; gaps G1–G7 identificados e corrigidos |

---

## Revisão 24/jun/2026

**Escopo:** 22 arquivos em `evolution-go/` + código `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` + `custom/config/initializers/messaging_provider_registry.rb`

**Fontes:** código Evolution Node implementado (60+ arquivos em `custom/`), collection Postman, OpenAPI evolution-go

---

## Veredito executivo

| Dimensão | Nota | Comentário |
|----------|------|------------|
| Cobertura API / webhooks | **A** | 26 ADRs + Postman audit cobrindo todos os endpoints MVP |
| Alinhamento fork Node implementado | **B−** | Gaps críticos encontrados na detecção de envelope e registry |
| Prontidão para codificar Fase 0 | **B** | Bloqueado por G4 (prepend collision) e G6 (webhook_token) até correção |
| Completude vs z-api (peer) | **B+** | Tem `error-handling.md` e `troubleshooting.md` que z-api não tem |
| Fixtures E2E | **⚠️** | Templates sintéticos — confirmar com instância real |

---

## Gaps identificados e corrigidos

| # | Gap | Gravidade | Arquivo(s) corrigido(s) |
|---|-----|-----------|------------------------|
| G1 | `EvolutionGo::ApiError` ausente do spec-design e tasks | Alta | `spec-design.md`, `tasks.md` |
| G2 | `EvolutionGoConnectionChannel` (ActionCable) ausente do spec-design e tasks | Alta | `spec-design.md`, `tasks.md` |
| G3 | `EvolutionGoController` spec sem `process_payload` e `sanitized_job_payload` | Alta | `spec-design.md` |
| G4 | **CRÍTICO** — prepend collision: evolution Node `return` (sem `super`) silencia eventos Go; mesma `evolution_envelope?` captura ambos os providers | **Crítica** | `decisions.md` (§27), `spec-design.md`, `tasks.md` (I0.7), `coordination-with-evolution-api.md` |
| G5 | Registry format errado no spec — bloco vs posicional (código real usa posicional) | Alta | `spec-design.md` |
| G6 | `webhook_secret` inconsistente com evolution Node implementado (`webhook_token`) | Alta | Todos os 10 arquivos afetados (sed replace) |
| G7 | Migration para índice único `instance_name` ausente de Fase 0 tasks | Média | `tasks.md` (I0.6) |

---

## Detalhamento — G4 (prepend collision)

O `Custom::Webhooks::WhatsappEventsJob` implementado:

```ruby
def evolution_envelope?(params)
  params[:event].present? && evolution_instance_name(params).present?
end

def evolution_instance_name(params)
  params[:instance_name].presence || params[:instance]
end
```

Evolution Go tem **o mesmo envelope** (`event` + `instance`). Sem cuidado:

1. Evolution_go controller injeta `instance_name: params[:instance_name]` (como evolution node)
2. `evolution_envelope?` → true para eventos Go
3. `find_evolution_channel` (procura `provider: 'evolution'`) → nil
4. `unless channel ... return` — **descarte silencioso**, nunca chama `super`

**Fix documentado em decisions.md §27:**
- Controller Go injeta `evolution_go_instance_name:` (não `instance_name:`) e remove `instance` do payload bruto
- Prepend Go detecta por `params[:evolution_go_instance_name].present?`
- Prepend Node: `return super(params)` (não `return`) no guard canal não encontrado — task I0.7

---

## Inventário por arquivo

| Arquivo | Papel | Estado após revisão |
|---------|-------|---------------------|
| [README.md](./README.md) | Landing | ✅ |
| [status.md](./status.md) | Estado | ✅ atualizado |
| [decisions.md](./decisions.md) | ADRs | ✅ §27 adicionado; webhook_token corrigido |
| [spec-design.md](./spec-design.md) | Contratos Ruby | ✅ ApiError, ConnectionChannel, controller, registry, job prepend |
| [tasks.md](./tasks.md) | Backlog | ✅ I0.6/I0.7, I1.1/I1.5/I1.6/I1.7 adicionados |
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Coexistência | ✅ seção collision adicionada |
| [api-reference.md](./api-reference.md) | Contratos REST | ✅ sem alteração necessária |
| [webhook-events.md](./webhook-events.md) | Payloads | ✅ sem alteração necessária |
| [provider-config-mapping.md](./provider-config-mapping.md) | JSONB | ✅ webhook_token corrigido |
| [error-handling.md](./error-handling.md) | Erros HTTP | ✅ sem alteração (bem documentado) |
| [implementation-plan.md](./implementation-plan.md) | Fases | ✅ webhook_token corrigido |
| [feature-mapping.md](./feature-mapping.md) | Paridade | ✅ webhook_token corrigido |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI | ✅ webhook_token corrigido |
| [inbox-business-rules.md](./inbox-business-rules.md) | Regras | ✅ webhook_token corrigido |
| [validation-checklist.md](./validation-checklist.md) | E2E | ⚠️ não executado — próximo passo operacional |
| [troubleshooting.md](./troubleshooting.md) | Runbook | ✅ webhook_token corrigido |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | Comparativo | ✅ sem alteração |
| [postman-validation.md](./postman-validation.md) | Audit | ✅ sem alteração |

---

## Diferenças intencionais vs z-api (peer)

| Aspecto | Evolution Go | Z-API | Notas |
|---------|-------------|-------|-------|
| `error-handling.md` | ✅ | ❌ | Evolution Go tem runbook de erros |
| `troubleshooting.md` | ✅ | ❌ | Z-API cria após piloto |
| `ConnectionEvents` separado | ✅ `EvolutionGo::ConnectionEvents` | ✅ | Alinhado com Node/Z-API |
| `Broadcaster` dedicado | ✅ | ❌ | `EvolutionGo::Broadcaster` + disconnect toast |

---

## Revisão jul/2026 (pós-implementação + review)

| Área | Ação |
|------|------|
| `webhook-events.md` | SEND_MESSAGE echo sync, EventNames, aliases, canonical subscribe |
| `decisions.md` | §7/§18/§25 updated; ADR §28–§31 (echo, EventNames, latency, SSRF) |
| `provider-config-mapping.md`, `inbox-business-rules.md` | Proxy `host` not `address` |
| `troubleshooting.md`, `status.md`, `README.md` | Sync with current behavior |
| `api-reference.md`, `postman-validation.md`, `spec-design.md`, `frontend-wizard-spec.md` | ✅ alinhados jul/2026 |
| Código | 23 review items: P1–P3 fixes applied jul/2026 |

---

## Revisão 09/jul/2026 (doc sync vs código)

Cruzamento código `custom/.../evolution_go/` × docs. **Conclusão:** docs de status/tasks estavam majoritariamente corretos; vários docs de *planejamento* ainda descreviam Go como “só documentação” ou features já shipped como Fase 3.

| Arquivo | Drift | Correção |
|---------|-------|----------|
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | “Estado Go: somente documentação”; PROVIDERS sem `evolution_go`; registry em bloco; `EvolutionGoWhatsapp` / `useGatewayWhatsappWizard` | Reescrito para estado implementado |
| [feature-mapping.md](./feature-mapping.md) | Location/contact/sticker/logout ainda “Fase 3” | Marcados ✅ / parcial |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | Nome `EvolutionGoWhatsapp.vue`; composable compartilhado como se existisse | Nomes reais + nota “não implementado” |
| [decisions.md](./decisions.md) §11 | Wizard ADR desatualizado | Aponta `EvolutionGo.vue` + composables dedicados |
| [README.md](./README.md) / [status.md](./status.md) / [tasks.md](./tasks.md) | Escopo “planejado”; API inbox incompleta; I3 ❌ | Ajustados |

| Aspecto planejado | Código real |
|-------------------|-------------|
| `ConnectionEvents` inline no `ConnectionService` | ✅ classe separada `EvolutionGo::ConnectionEvents` |
| `useGatewayWhatsappWizard` | ❌ não existe — composables `evolution_go/*` |
| `EvolutionGoWhatsapp.vue` | `EvolutionGo.vue` |

---

## O que ainda falta (não bloqueante)

| Item | Bloqueio | Ação |
|------|----------|------|
| Fixtures JSON reais | Sem instância Go | [validation-checklist.md](./validation-checklist.md) E2E |
| JID field real no `GET /instance/status` | Formato Go não confirmado | Capturar no E2E |
| `CONNECTION` payload real | Template sintético | `connection_event.json` E2E |
| Presence → typing dashboard | ✅ | `TypingListener` + `PresenceSyncJob` + `ApiClient#set_presence` |
| Versão Go congelada | Operador informa | `evolution-target-version.txt` |
