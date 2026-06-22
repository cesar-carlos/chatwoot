# Tarefas — Provider Evolution Go

**Escopo:** integração no fork Chatwoot. Evolution Go roda **fora** do repositório (instância do operador).

| ID | Tarefa | Status | Doc |
|----|--------|--------|-----|
| D0 | Documentação consolidada (integração only) | ✅ feito | [README.md](./README.md), [status.md](./status.md) |
| I0 | Fase 0 — infra registry + prepends | ❌ pendente | [implementation-plan.md § Fase 0](./implementation-plan.md) |
| I1 | Fase 1 — MVP texto + QR | ❌ pendente | idem § Fase 1 |
| I2 | Fase 2 — mídia, READ_RECEIPT, settings | ❌ pendente | idem § Fase 2 |
| E1 | Checklist E2E (instância operador) | ❌ durante I1 | [validation-checklist.md](./validation-checklist.md) |

---

## I0 — Fase 0 (infra)

Não depende de servidor Go — registry e prepends:

| # | Entrega |
|---|---------|
| 0.1 | `# FORK:` `evolution_go` em `PROVIDERS` |
| 0.2 | Registry `evolution_go` |
| 0.3 | Capability `unlimited_session` |
| 0.4 | Prepend `MessageWindowService` |
| 0.5 | Rota + controller stub `EvolutionGoController` |

---

## I1 — Fase 1 (MVP)

| # | Entrega |
|---|---------|
| 1.1 | `EvolutionGo::ApiClient` |
| 1.2 | `EvolutionGo::ConnectionService` |
| 1.3 | `EvolutionGoService` + `EvolutionGoNormalizer` |
| 1.4 | Webhook controller + prepend job |
| 1.5 | Wizard Vue + card `Whatsapp.vue` |
| 1.6 | Specs com fixtures (sintéticas ou E2E) |

**Pré-requisito operador:** instância Evolution Go acessível (`base_url`, `GLOBAL_API_KEY`, licença ativa).

---

## E1 — Validação E2E (paralelo a I1)

Executar [validation-checklist.md](./validation-checklist.md) contra a instância do operador — **não** bloqueia início do código.

Entregas:
- `spec/fixtures/evolution_go/*.json` (capturas reais)
- `evolution-target-version.txt` com versão do servidor
- Confirmar ADR §24–26 no ambiente real

---

## Dependências

```
I0 (Fase 0) → I1 (Fase 1 MVP) → I2 (Fase 2)
                    │
                    └── E1 (E2E) em paralelo — fixtures + versão
```

Coordenação Node: [coordination-with-evolution-api.md](./coordination-with-evolution-api.md)
