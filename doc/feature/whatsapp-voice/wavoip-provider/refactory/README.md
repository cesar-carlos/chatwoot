# Wavoip — plano de refatoração e correção

Resultados da revisão de código realizada em **26 jun. 2026**, cobrindo bugs confirmados,
gaps de comportamento e oportunidades de qualidade/performance identificados na implementação
das fases 1–4 + conclusões A–E.

**Revisão gerada a partir de:** leitura integral de todos os arquivos `custom/**/wavoip/**`,
`lib/voice/**`, `lib/wavoip/**`, `composables/wavoip/**`, `models/channel/wavoip.rb`,
todos os services/jobs Wavoip e da página de configuração `WavoipCallingPage.vue`.

---

## Documentos desta pasta

| Documento | Conteúdo |
|-----------|---------|
| [bugs.md](./bugs.md) | 5 bugs com comportamento errado confirmado |
| [gaps.md](./gaps.md) | 6 gaps — features implementadas com semântica incompleta |
| [code-quality.md](./code-quality.md) | Duplicações, estado global, perf e inconsistências |
| [plan.md](./plan.md) | **Plano priorizado** — fases, critérios de pronto e ordem de execução |

---

## Resumo executivo

| Categoria | Itens | Status |
|-----------|-------|--------|
| Bugs | 5 | ✅ Concluído |
| Gaps | 11 | ✅ Concluído |
| Qualidade/Perf | 14 | ✅ Concluído |
| **Total** | **30/30** | **Refatoração concluída** |

Todas as fases R1, R2 e R3 foram implementadas conforme [plan.md](./plan.md).
Suite de regressão: 104 RSpec + 83 Vitest (Wavoip custom).

### Top 5 — corrigidos (R1)

1. **[BUG-01]** `removePendingOffer` rejeita promises em espera — `acceptIncomingCall` não trava mais.
2. **[GAP-01]** `offline_fallback: 'none'` bloqueia escalação por timeout (incl. `EscalateRingJob`).
3. **[GAP-02]** `accepted_by_agent_id` com retry exponencial (3 tentativas) e aviso em falha final.
4. **[BUG-02]** Alertas de chamada usam i18n do idioma ativo do usuário.
5. **[GAP-03]** Token rotacionado força reconexão do SDK sem reload de página.

---

## Contexto — estado antes desta revisão

- **MVP código:** ~95% (fases 0–4 + A–E code-complete)
- **Piloto produção:** ~60% (bloqueado em webhooks CALL live)
- **Sem regressão nesta revisão:** nenhum dos itens abaixo derruba o fluxo feliz de outbound já validado em E2E

Ver [../implementation-plan.md](../implementation-plan.md) para contexto de fases e [../spike-notes.md](../spike-notes.md) para gates G0.x.
