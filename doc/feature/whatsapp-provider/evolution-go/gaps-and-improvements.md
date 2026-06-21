# Gaps e melhorias — documentação Evolution Go

Reavaliação completa da pasta `evolution-go/` (jun/2026). **Fase: planejamento** — sem implementação de código.

**Como usar:** itens 🔴 exigem spike runtime; 🟠 durante implementação; 🟡 qualidade contínua.

**Última atualização doc:** jun/2026 — revisão completa; ver [../STATUS.md](../STATUS.md).

---

## Resumo executivo

| Área | Estado | Notas |
|------|--------|-------|
| Cobertura estrutural | ✅ | 25 arquivos + `sync-documentation-links.sh` |
| ADRs | ✅ | §1–23 fechados (§22 global_api_key, §23 reconnect) |
| Contratos Ruby/UI | ✅ | spec-design, wizard + sequence diagram |
| Coexistência Node | ✅ | coordination-with-evolution-api.md |
| Spike runtime | ❌ | **Único bloqueio principal** — fixtures reais |
| Paths não confirmados | ⚠️ | advanced-settings, alguns Group/Chat — marcados no doc |

**Score doc:** ~**92%** — pronta para implementação após spike P1.

---

## 🔴 Pendente — só resolve com spike (P1)

### G1 — Fixtures runtime

| Item | Entrega |
|------|---------|
| `send_text_response.json` | Confirmar `data.Info.ID` |
| `message_inbound.json` | Confirmar `key.id` inbound |
| `connection_event.json` | Payload `CONNECTION` real |
| `qrcode_event.json` | Payload `QRCODE` real |
| `read_receipt.json` | Fase 2 |

**Ação:** [validation-checklist.md](./validation-checklist.md) · template [spec/fixtures/evolution_go/README.md](../../../spec/fixtures/evolution_go/README.md)

### G2 — `phone_number` pós-connect

Documentado em [api-reference.md § Status](./api-reference.md) com ordem de fallback (`jid`/`myJid` → CONNECTION → MESSAGE). **Confirmar campo exato no spike.**

### G3 — Swagger audit (paths)

| Path | Estado doc |
|------|------------|
| `POST /instance/{id}/advanced-settings` | ⚠️ planejado — [api-reference.md](./api-reference.md) |
| Group `/group/list`, `/group/my` | ⚠️ — [documentation-links.md](./documentation-links.md) |

**Ação:** `./sync-documentation-links.sh` + Swagger runtime

---

## ✅ Melhorias aplicadas (jun/2026)

| # | Melhoria | Arquivo(s) |
|---|----------|--------------|
| M1 | Tabela duplicada removida | `webhook-events.md` |
| M2 | Casing PascalCase/camelCase + helpers | `api-reference.md`, `webhook-events.md` |
| M3 | `delete_instance(instance_id)` | `spec-design.md` |
| M4 | Contagem ADRs §1–23 | `implementation-readiness.md`, `decisions.md` |
| M5 | `evolution_go` em docs pai | `gaps-and-blockers.md`, `implementation-decision-tree.md`, `feature-mapping.md`, `implementation-plan-second-whatsapp-provider.md` |
| M6 | N/A docs Node-only | Documentado em gaps original |
| M7 | ⚠️ em Group paths | `documentation-links.md` |
| M8 | `ignore_status` semântica | `provider-config-mapping.md` |
| M9 | `tasks.md` operacional | `tasks.md` |
| M10 | Runbook licença | `troubleshooting.md` |
| — | ADR §22 `global_api_key` fechado | `decisions.md` |
| — | ADR §23 reconnect + webhook | `decisions.md`, `troubleshooting.md` |
| — | Contrato API wizard JSON | `frontend-wizard-spec.md` |
| — | Sequence diagram wizard | `frontend-wizard-spec.md` |
| — | Node vs Go — quando escolher | `provider-comparison.md` |
| — | Coexistência providers | `coordination-with-evolution-api.md` |
| — | `sync-documentation-links.sh` | `evolution-go/sync-documentation-links.sh` |
| — | Status + advanced-settings § | `api-reference.md` |
| — | READ_RECEIPT template bruto | `webhook-events.md` |
| — | `reconnect!` em ConnectionService | `spec-design.md` |
| — | `subscribe` persistido p/ reconnect | `provider-config-mapping.md` |
| — | Revisão consolidada fork | `../STATUS.md` |
| — | `gaps-and-blockers` alinhado ao código | `../gaps-and-blockers.md` |

---

## Critério "doc pronta para implementação"

| Critério | Status |
|----------|--------|
| Endpoints Fase 1 com link oficial | ✅ |
| ADRs rota/auth/send/source_id/reconnect | ✅ |
| UI wizard + contrato API interna | ✅ |
| Feature matrix | ✅ |
| Troubleshooting + errors + licença | ✅ |
| Node vs Go decision guide | ✅ |
| Fixtures reais | ❌ |
| CONNECTION/QRCODE payload confirmado | ⚠️ template |
| phone_number pós-connect | ⚠️ fallback documentado |
| advanced-settings path | ⚠️ Swagger |

---

## Prioridade restante

```
P1 Spike → fixtures (G1, G2, G3)
    ↓
I0 Fase 0 (registry + prepends)
    ↓
I1 Fase 1 MVP texto
```

Ver [tasks.md](./tasks.md).
