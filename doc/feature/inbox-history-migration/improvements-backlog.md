# Inbox History Migration — Improvements backlog

Pós-MVP. Não bloqueia o uso atual.

---

## Já no MVP

- Move completo WhatsApp A → B (Cloud / Evolution / Evolution Go / Twilio WA)
- Move completo API/Webhook A → B (preserva `source_id`; same-type)
- Move cross-channel WhatsApp ↔ API/Webhook (histórico/leitura; identity nativa no destino)
- Idempotência no destino API (reusa CI do contato); WA same-family preserva `source_id` sem phone
- Anti-steal sem `ContactInboxBuilder`; merge inclui resolved + `additional_attributes`
- Lock de inbox no POST; UI com destino/progresso/falhas parciais/empty state
- Remount + merge de peers existentes (workflow executions / AppliedSla / CSAT / Calls)
- Job + tabela de status/stats + polling UI (`pending` + `running`)
- Lock em `pending` **e** `running`; stale pending/running (>2h) auto-failed
- Stale expirado também no `GET move_history_status` (UI não fica presa)
- Colisão de `source_id` → peer `failed` (sem “steal” do ContactInboxBuilder)
- Stats por conversa (`moved`/`merged`/`skipped`/`failed`/`total`)
- Confirmação por nome da inbox
- Admin-only
- Specs `spec/custom/…`
- Docs nesta pasta

---

## P1 — Alto valor / baixo risco

| ID | Item | Notas |
|----|------|-------|
| IHM-P1-1 | Preview count antes de confirmar | Exibir `conversations.count` / peers na UI |
| IHM-P1-2 | Toast + link para inbox destino ao `completed` | Navegação pós-migração |
| IHM-P1-3 | Detectar migration `running` stale | ✅ Heartbeat > 2h → `failed` (guard + status GET) |
| IHM-P1-4 | Filtrar destino por provider mais seguro | Ex.: avisar Evolution→Cloud com grupos |
| IHM-P1-5 | Activity note na conversa mergeada | “History merged from inbox X” |
| IHM-P1-6 | Lock pending + running | ✅ `blocking_progress` no guard + job |
| IHM-P1-7 | Remount/reparent Calls | ✅ Remounter + ConversationMerger |

---

## P2 — Produto / canais

| ID | Item | Notas |
|----|------|-------|
| IHM-P2-1 | Telegram → Telegram | Remapper de `source_id` + `additional_attributes.chat_id` |
| IHM-P2-2 | Email → Email | `source_id` = email |
| IHM-P2-3 | API / Webhook → API | ✅ Remount preservando `source_id` (não archive) |
| IHM-P2-6 | Archive cross-channel WA ↔ API | ✅ Remount com identity nativa no destino; outbound não garantido |
| IHM-P2-4 | Seleção parcial (por data / status) | Expandir além de “caixa inteira” |
| IHM-P2-5 | Sub-jobs por lote | Inboxes com dezenas de milhares de peers |
| IHM-P2-7 | Archive para Telegram / Email / etc. | Ainda backlog (outros canais) |

---

## P3 — Ops / observabilidade

| ID | Item | Notas |
|----|------|-------|
| IHM-P3-1 | Super Admin list de migrations | Contas multi-inbox |
| IHM-P3-2 | Métricas Sidekiq / duração média | |
| IHM-P3-3 | Feature flag jsonb via `FeatureStore` | Se precisar hide por conta |

---

## Explicitamente fora (por enquanto)

- Mover via bulk bar do chat list
- `UPDATE` só de `conversations.inbox_id`
- i18n community languages (manter EN no fork)

---

*Última atualização: 25/jul/2026*
