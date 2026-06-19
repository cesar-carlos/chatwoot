# Pesquisa de mensagens dentro da conversa

Levantamento e plano para busca no contexto da conversa aberta, incluindo **texto e transcrições de áudio**.

## Documentos

| Arquivo | Conteúdo |
|---------|----------|
| [current-state.md](./current-state.md) | Estado atual: pesquisa global, menu, scroll, transcrição |
| [audio-transcription-search.md](./audio-transcription-search.md) | **Integração áudio transcrito** — BD, SQL, frontend |
| [rules-compliance-review.md](./rules-compliance-review.md) | Revisão contra rules do projeto |
| [ux-improvements.md](./ux-improvements.md) | Melhorias UI/UX (UX-M*, P1–P3) |
| [ui-design.md](./ui-design.md) | Especificação visual MVP |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Decisões D1–D19 |
| [implementation-plan.md](./implementation-plan.md) | Plano de implementação |
| [api-endpoints.md](./api-endpoints.md) | **Matriz de endpoints** — 1 rota nova, reutilização por fase |
| [improvements-backlog.md](./improvements-backlog.md) | Backlog pós-MVP |

## Resumo executivo

| Pergunta | Resposta |
|----------|----------|
| Pesquisa em áudio transcrito? | **Sim** — join `attachments.meta` no finder (Fase C) |
| Onde está o texto? | `attachments.meta` (`transcribed_text` + `transcription.text`) — Groq e OpenAI |
| Mudança no backend? | **1 endpoint novo** — `GET .../messages/search` ([api-endpoints.md](./api-endpoints.md)) |
| Mais completo que global SQL? | **Sim** (global ILIKE não busca transcrição; OpenSearch sim) |
| Entrada UI (MVP) | Menu ⋮ → Pesquisar nesta conversa |

## Status da implementação

| Camada | Estado (jun/2026) |
|--------|-------------------|
| Backend (`custom/` finder, service, controller, rota) | ❌ Não implementado |
| Frontend (Dialog, composables, API fork) | ❌ Não implementado |
| Documentação / plano | ✅ Revisado — ver [rules-compliance-review.md](./rules-compliance-review.md) §9 |

**Nota:** o store `conversationSearch.js` é da **pesquisa global** (`/search`), não desta feature.

## Entrega em fases (recomendação pós-reavaliação)

| Fase | Escopo | Objetivo |
|------|--------|----------|
| **A — Happy path** | Backend + dialog + busca + lista + clique | Funciona end-to-end |
| **B — Robustez** | Merge Vuex, toast falha, loading thread, 422 | Corrige bugs reais do scroll |
| **C — Polish** | Badge mic, nota privada, transcrição no finder, estados UX restantes | Paridade com catálogo UX-M* |

Detalhe: [implementation-plan.md](./implementation-plan.md) § "Fases de entrega".

## Próximo passo

1. **Release 1** — Fase A ([implementation-plan.md](./implementation-plan.md) § Fase A)
2. **Release 2** — Fase B (scroll robusto)
3. **Release 3** — Fase C (MVP completo + áudio)
4. **Releases 4–6** — P1 → P2 → P3 (roadmap completo no plano)

Roadmap: [implementation-plan.md](./implementation-plan.md) § "Roadmap completo".
