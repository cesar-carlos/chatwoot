# Status — Provider Evolution Go

**Escopo do fork:** integração Chatwoot ↔ Evolution Go (REST + webhooks). A Evolution Go é **infra externa** — o fork **não** provisiona nem sobe o servidor Go.

**Última revisão:** 22/jun/2026 · **doc pronta para implementação**

---

## Legenda

| Status | Significado |
|--------|-------------|
| ✅ | Documentado / pronto para codificar |
| ⚠️ | Contrato documentado; confirmar em E2E com instância do operador |
| ❌ | Não iniciado no código |

---

## Resumo

| Área | Estado | Notas |
|------|--------|-------|
| ADRs §1–26 | ✅ | [decisions.md](./decisions.md) |
| Contratos Ruby/UI | ✅ | [spec-design.md](./spec-design.md) |
| API + webhooks | ✅ | [api-reference.md](./api-reference.md), [webhook-events.md](./webhook-events.md) |
| Postman audit | ✅ | [postman-validation.md](./postman-validation.md) |
| Coexistência Node | ✅ | [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) |
| Código `custom/` | ❌ | Nenhuma classe Evolution Go |
| Fixtures reais | ⚠️ | Templates em `spec/fixtures/evolution_go/` — preencher no E2E |
| Fase 2 (settings, mídia) | ⚠️ | Body `advanced-settings`, `downloadimage` vs `downloadmedia` |

---

## Código Chatwoot — pendente

| Item | Status |
|------|--------|
| `# FORK:` `PROVIDERS` + `evolution_go` | ❌ (só `evolution` hoje) |
| Registry + prepends | ✅ existem para Node — **reusar** |
| ApiClient, ConnectionService, Normalizer, Service | ❌ |
| Wizard Vue | ❌ |

Detalhe por fase: [implementation-plan.md](./implementation-plan.md) · tarefas: [tasks.md](./tasks.md)

---

## Lacunas conhecidas (não bloqueiam Fase 0–1)

| # | Tema | Mitigação |
|---|------|-----------|
| G1 | Fixtures JSON reais | ADRs + Postman como contrato; capturar no [E2E](./validation-checklist.md) |
| G2 | Campo JID pós-connect | Fallback documentado em [api-reference.md](./api-reference.md) |
| G3 | `advanced-settings` body | ADR §26 + E2E §2b do [checklist](./validation-checklist.md) |
| G4 | `downloadimage` vs `downloadmedia` | ADR §25 — primário OpenAPI, fallback Postman |

---

## Critério "pronto para codificar"

- [x] Endpoints Fase 1 documentados
- [x] ADRs fechadas
- [x] Wizard + API interna especificados
- [x] Troubleshooting operacional
- [x] Audit Postman
- [ ] Fixtures reais (opcional até E2E)
- [ ] Versão Go do operador em [evolution-target-version.txt](./evolution-target-version.txt)

**Próximo passo:** [tasks.md](./tasks.md) — Fase 0 → Fase 1.
