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

| Categoria | Itens | Severidade máxima |
|-----------|-------|-------------------|
| Bugs | 5 | Alta (deadlock no accept) |
| Gaps | 11 | Alta (`none` não bloqueia escalação) |
| Qualidade/Perf | 14 | Média |
| **Total** | **30** | — |

### Top 5 — corrigir antes do piloto em produção

1. **[BUG-01]** `removePendingOffer` não rejeita promises em espera → `acceptIncomingCall` trava indefinidamente.
2. **[GAP-01]** `offline_fallback: 'none'` não bloqueia a escalação por timeout → contradição direta com o que o admin configurou.
3. **[GAP-02]** `accepted_by_agent_id` pode não ser persistido sem nenhum erro visível.
4. **[BUG-02]** Alertas de chamada em inglês hardcoded para usuários em qualquer idioma.
5. **[GAP-03]** Token rotacionado não reconecta o SDK até reload da página.

---

## Contexto — estado antes desta revisão

- **MVP código:** ~95% (fases 0–4 + A–E code-complete)
- **Piloto produção:** ~60% (bloqueado em webhooks CALL live)
- **Sem regressão nesta revisão:** nenhum dos itens abaixo derruba o fluxo feliz de outbound já validado em E2E

Ver [../implementation-plan.md](../implementation-plan.md) para contexto de fases e [../spike-notes.md](../spike-notes.md) para gates G0.x.
