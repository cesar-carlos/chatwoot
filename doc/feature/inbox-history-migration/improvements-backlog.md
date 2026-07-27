# Inbox History Migration — Improvements backlog

Pós-MVP. Não bloqueia o uso atual.

---

## Já no MVP

- Move completo WhatsApp A → B (Cloud / Evolution / Evolution Go / Twilio WA)
- Move completo API/Webhook A → B (preserva `source_id`; same-type)
- Move cross-channel WhatsApp ↔ API/Webhook (histórico/leitura; identity nativa no destino)
- Idempotência no destino API (reusa CI do contato); WA same-family preserva `source_id` sem phone
- Anti-steal sem `ContactInboxBuilder`; merge inclui resolved + `additional_attributes`
- Lock de inbox no POST (ordem por id); UI com destino/progresso/falhas parciais/empty state
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
- Preview count antes de confirmar (IHM-P1-1)
- Toast + link para inbox destino ao `completed` (IHM-P1-2)
- Aviso Evolution→Cloud com grupos (IHM-P1-4)
- Activity note na conversa mergeada (IHM-P1-5)
- Cleanup de ContactInbox órfão na origem (`delete`, não `destroy!`)
- Stats `failed` sem inflar CI vazio
- Clear `assignee_agent_bot` no remount quando bot não está no destino
- UI exclui a própria inbox com comparação numérica de id
- HTTP 503 `unavailable` quando a tabela/migrations não estão aplicadas
- Falha fatal do service sem re-raise (evita retry Sidekiq)
- Toast diferencia `completed` (sem falhas) de `completed with N failure(s)` (IHM-BF-1)
- Processamento de convs por contato em `order(id: :desc)`: conversa mais recente vira container (IHM-BF-2)
- `derived_source_id` para WA usa `gsub(/\D/, '')` — normaliza qualquer char não-dígito (IHM-BF-3)
- API → WA Evolution: grupos com `@g.us` JID em `contact.identifier` agora são migrados (antes falhavam com UUID source_id) (IHM-BF-4)

---

## P1 — Alto valor / baixo risco

| ID | Item | Notas |
|----|------|-------|
| IHM-P1-1 | Preview count antes de confirmar | ✅ |
| IHM-P1-2 | Toast + link para inbox destino ao `completed` | ✅ |
| IHM-P1-3 | Detectar migration `running` stale | ✅ Heartbeat > 2h → `failed` (guard + status GET) |
| IHM-P1-4 | Filtrar destino por provider mais seguro | ✅ Aviso Evolution→Cloud com grupos |
| IHM-P1-5 | Activity note na conversa mergeada | ✅ |
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
| IHM-P2-8 | Heartbeat por conversa (não só por CI) | Peer único com muitas mensagens pode passar de 2h sem heartbeat |
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

*Última atualização: 27/jul/2026 (IHM-BF-1..3: bug fixes pós-deploy)*
