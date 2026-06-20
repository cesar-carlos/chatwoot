# Pesquisa de mensagens dentro da conversa

Planejamento para busca no contexto da conversa aberta, incluindo **texto e transcrições de áudio**.

> **Fonte normativa:** [implementation-plan.md](./implementation-plan.md), consolidado e reavaliado contra o código em 19 de junho de 2026. Os outros documentos preservam a investigação e servem como referência, mas podem conter alternativas superadas.

## Documentos

| Arquivo | Conteúdo |
|---------|----------|
| [current-state.md](./current-state.md) | Estado atual: pesquisa global, menu, scroll, transcrição |
| [audio-transcription-search.md](./audio-transcription-search.md) | **Integração áudio transcrito** — BD, SQL, frontend |
| [rules-compliance-review.md](./rules-compliance-review.md) | Revisão contra rules do projeto |
| [ux-improvements.md](./ux-improvements.md) | Melhorias UI/UX (UX-M*, P1–P3) |
| [ui-design.md](./ui-design.md) | Especificação visual MVP |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Decisões D1–D19 |
| [implementation-plan.md](./implementation-plan.md) | **Plano consolidado e fonte de verdade** |
| [api-endpoints.md](./api-endpoints.md) | **Matriz de endpoints** — 1 rota nova, reutilização por fase |
| [improvements-backlog.md](./improvements-backlog.md) | Backlog pós-MVP |

## Resumo executivo consolidado

| Pergunta | Resposta |
|----------|----------|
| Pesquisa em áudio transcrito? | **Sim, na primeira entrega** — join `attachments.meta` |
| Onde está o texto? | `attachments.meta` (`transcribed_text` + `transcription.text`) — Groq e OpenAI |
| Mudança no backend? | **1 endpoint novo** — `GET .../messages/search` ([api-endpoints.md](./api-endpoints.md)) |
| Mais completo que global SQL? | **Sim** (global ILIKE não busca transcrição; OpenSearch sim) |
| Entrada UI | Menu ⋮ / painel lateral / ⌘F — Pesquisar nesta conversa |
| Scroll antigo | Mescla diretamente o resultado já retornado pela busca |
| Paginação | 15 resultados + `has_more`, sem `COUNT DISTINCT` |
| Requests | Debounce + cancelamento via `AbortController` |
| Alterações upstream | Rota, hook do controller e integração em `MoreActions` |

## Status da implementação

| Camada | Estado (jun/2026) |
|--------|-------------------|
| Backend (`custom/` finder, controller, rota) | ✅ Implementado |
| Frontend (painel lateral, composables, API) | ✅ Implementado |
| Specs RSpec + Vitest | ✅ Implementado (API, finder, lib, composables) |
| Baseline `EXPLAIN ANALYZE` (dev local) | ✅ Documentado em `implementation-plan.md` §6.1.1 |
| `EXPLAIN` em conversa grande (produção) | ⏳ `rake conversation_message_search:explain` |
| Matriz de aceite §11 | ⏳ `rake conversation_message_search:acceptance` + teste manual |

**Nota:** o store `conversationSearch.js` é da **pesquisa global** (`/search`), não desta feature.

## Forma de entrega

Uma entrega vertical pronta para uso, implementada em quatro checkpoints internos:

1. backend verificável;
2. busca no painel lateral;
3. navegação confiável;
4. lint e matriz de aceite.

Texto, transcrição e salto para mensagens antigas fazem parte da mesma entrega.
