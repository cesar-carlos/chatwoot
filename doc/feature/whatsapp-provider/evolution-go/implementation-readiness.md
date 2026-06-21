# Prontidão para implementação — Evolution Go

Checklist do que está **documentado** vs **pendente** antes de escrever código em `custom/`.

**Última revisão:** jun/2026 · **score doc ~92%**

---

## Legenda

| Status | Significado |
|--------|-------------|
| ✅ | Pronto para implementar |
| ⚠️ | Documentado com lacuna — spike necessário |
| ❌ | Não iniciado (código ou runtime) |

---

## Documentação fork

| Documento | Status |
|-----------|--------|
| Core (README, api-reference, decisions §1–23) | ✅ |
| webhook-events, spec-design, frontend-wizard-spec | ✅ |
| gaps-and-improvements, coordination, tasks | ✅ |
| sync-documentation-links.sh | ✅ |
| inbox-business-rules, provider-config (`advanced-settings`) | ⚠️ path REST |

Índice completo: [README.md](./README.md)

---

## Spike runtime (bloqueia Fase 1)

| Item | Status |
|------|--------|
| Fixtures JSON reais | ❌ |
| Versão Go congelada | ❌ |
| Campo JID pós-connect confirmado | ⚠️ fallback documentado |
| advanced-settings path Swagger | ⚠️ |

Template: [spec/fixtures/evolution_go/README.md](../../../spec/fixtures/evolution_go/README.md)

---

## Infra Chatwoot (Fase 0)

| Item | Status |
|------|--------|
| `# FORK:` PROVIDERS + `evolution_go` | ❌ (só `evolution` hoje) |
| Registry + prepends | ✅ existem para Node — **reusar** para Go |
| Evolution Node em `custom/` | ✅ Fase 0–3 |

Ver [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) · [../STATUS.md](../STATUS.md)

---

## Decisões

| # | Tema | Status |
|---|------|--------|
| §21 | Wizard via backend | ✅ |
| §22 | `global_api_key` persistido | ✅ |
| §23 | Reconnect reenvia webhook | ✅ |
| Spike | Inbound `source_id`, JID | ⚠️ |

---

## Critério "planejamento completo"

- [x] Endpoints Fase 1 documentados
- [x] ADRs fechadas
- [x] Wizard + API interna + diagrama
- [x] Troubleshooting + licença + reconnect
- [x] Node vs Go + coexistência
- [x] Melhorias doc (jun/2026)
- [ ] Fixtures reais
- [ ] Versão Go congelada

**Próximo passo:** [tasks.md P1](./tasks.md) — spike Docker.

Detalhe gaps: [gaps-and-improvements.md](./gaps-and-improvements.md)
