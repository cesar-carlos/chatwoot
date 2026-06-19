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
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Decisões D1–D16 |
| [implementation-plan.md](./implementation-plan.md) | Plano de implementação |
| [improvements-backlog.md](./improvements-backlog.md) | Backlog pós-MVP |

## Resumo executivo

| Pergunta | Resposta |
|----------|----------|
| Pesquisa em áudio transcrito? | **Sim no MVP** — join `attachments.meta` no finder |
| Onde está o texto? | `attachments.meta` (`transcribed_text` + `transcription.text`) — Groq e OpenAI |
| Mudança no backend? | **Finder unificado** — sem novo endpoint nem coluna |
| Mais completo que global SQL? | **Sim** (global ILIKE não busca transcrição; OpenSearch sim) |
| Entrada UI (MVP) | Menu ⋮ → Pesquisar nesta conversa |

## Próximo passo

Implementar [implementation-plan.md](./implementation-plan.md) — Fase 1 com finder unificado (texto + transcrição).
