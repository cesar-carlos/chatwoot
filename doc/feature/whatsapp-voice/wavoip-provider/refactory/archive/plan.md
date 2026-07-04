# Plano de refatoração — Wavoip (arquivado)

> Conteúdo integral preservado para consulta histórica. Ver [../CHANGELOG.md](../CHANGELOG.md)
> para o resumo condensado.

Fonte única de prioridade e ordem de execução para todas as correções e melhorias
identificadas na revisão de 26 jun. 2026.

**Total de itens:** 32 (7 bugs + 11 gaps + 14 qualidade)
**Critério de pronto geral:** sem regressão nos testes existentes (104 RSpec + 83 Vitest examples)
+ spec específico para cada item corrigido.

---

## Mapa de prioridades

| ID | Documento | Título curto | Prioridade | Esforço | Fase |
|----|-----------|-------------|------------|---------|------|
| BUG-01 | [bugs.md](./bugs.md) | Deadlock em `acceptIncomingCall` | 🔴 Crítica | P | R1 |
| GAP-01 | [gaps.md](./gaps.md) | `none` não bloqueia escalação | 🔴 Crítica | P | R1 |
| GAP-02 | [gaps.md](./gaps.md) | `accepted_by_agent_id` sem retry | 🔴 Alta | M | R1 |
| BUG-02 | [bugs.md](./bugs.md) | Alertas hardcoded em inglês | 🟠 Alta | P | R1 |
| GAP-03 | [gaps.md](./gaps.md) | Token rotacionado não reconecta SDK | 🟠 Alta | M | R1 |
| BUG-03 | [bugs.md](./bugs.md) | Múltiplos `EscalateRingJob` por call | 🟠 Média | P | R2 |
| GAP-04 | [gaps.md](./gaps.md) | `PhoneNormalizer` assume Brasil | 🟠 Média | G | R2 |
| QC-01 | [code-quality.md](./code-quality.md) | `mark_webhook_verified!` duplicado | 🟡 Média | P | R2 |
| QC-02 | [code-quality.md](./code-quality.md) | `update_conversation` duplicado | 🟡 Média | P | R2 |
| QC-06 | [code-quality.md](./code-quality.md) | `assignee_scope` 2x SQL | 🟡 Média | P | R2 |
| QC-08 | [code-quality.md](./code-quality.md) | `ProcessWebhookJob` fila `:low` | 🟡 Média | P | R2 |
| GAP-07 | [gaps.md](./gaps.md) | `assignee` ≡ `assignee_or_inbox_members` | 🟡 Baixa | P | R3 |
| GAP-08 | [gaps.md](./gaps.md) | `notify_busy_agents` só no toque inicial | 🟡 Baixa | P | R3 |
| GAP-09 | [gaps.md](./gaps.md) | `administratorsToggle` sem contrato backend | 🟡 Baixa | P | R3 |
| GAP-10 | [gaps.md](./gaps.md) | `saveCallRouting` race last-write-wins | 🟡 Baixa | M | R3 |
| GAP-05 | [gaps.md](./gaps.md) | `ring_timeout_seconds` sem limite | 🟡 Baixa | P | R3 |
| GAP-06 | [gaps.md](./gaps.md) | Listener `statusChanged` vaza | 🟡 Baixa | P | R3 |
| GAP-11 | [gaps.md](./gaps.md) | Polling quando device já conectado | 🟡 Baixa | P | R3 |
| BUG-04 | [bugs.md](./bugs.md) | `isConnecting` false prematuro | 🟡 Baixa | P | R3 |
| BUG-05 | [bugs.md](./bugs.md) | `activeInboxId` não limpo no cancel | 🟡 Baixa | P | R3 |
| QC-03 | [code-quality.md](./code-quality.md) | `reload` redundante no `with_lock` | 🟢 Baixa | P | R3 |
| QC-04 | [code-quality.md](./code-quality.md) | String literal vs `INBOX_TYPES` | 🟢 Baixa | P | R3 |
| QC-05 | [code-quality.md](./code-quality.md) | Variável `normalized` morta | 🟢 Baixa | P | R3 |
| QC-07 | [code-quality.md](./code-quality.md) | `busy_agents` carrega Redis inteiro | 🟢 Baixa | M | R3 |
| QC-09 | [code-quality.md](./code-quality.md) | `DeviceStatusService` double reload | 🟢 Baixa | P | R3 |
| QC-10 | [code-quality.md](./code-quality.md) | `mediaByInbox` memory leak no disconnect | 🟢 Baixa | P | R3 |
| QC-11 | [code-quality.md](./code-quality.md) | `transition_allowed?` aceita terminal→terminal | 🟡 Baixa | P | R3 |
| QC-12 | [code-quality.md](./code-quality.md) | `webhook_url` silencia falta de `FRONTEND_URL` | 🟡 Baixa | P | R3 |
| QC-13 | [code-quality.md](./code-quality.md) | `onOutboundConnected` código morto | 🟢 Baixa | P | R3 |
| QC-14 | [code-quality.md](./code-quality.md) | `test_wavoip_webhook` bloqueia thread Puma | 🟡 Baixa | P | R3 |

**Esforço:** P = Pequeno (< 2h) · M = Médio (2–4h) · G = Grande (> 4h)

---

## Ordem de execução (como foi feito)

```
R1.1 (deadlock)
  → R1.2 (none + escalação)    ← par natural, mesmo arquivo
  → R1.4 (i18n)                ← quick win, sem dependência
  → R1.3 (attribution retry)   ← JS isolado
  → R1.5 (token rotation)      ← pode ser feito em paralelo com R1.3

R2.1 (idempotência escalação)
R2.3 (DRY backend)             ← pré-requisito para R2 mais seguro
  → R2.2 (phone normalizer)    ← risco maior, isolar em branch
R2.4 + R2.5                    ← sem dependências

R3 — batch único de PR pequenos por arquivo
```

---

## Rastreamento de progresso

Todos os 30 itens do mapa acima foram concluídos (✅), assim como os itens adicionais
encontrados em revisão pós-implementação (26 jun. 2026):

| ID | Descrição | Status |
|----|-----------|--------|
| BUG-POS-01 | `IncomingCallRecipients#users` retornava `InboxMember` em vez de `User` → `pluck(:pubsub_token)` lançava `PG::UndefinedColumn`; nenhum broadcast ActionCable chegava aos agentes online | ✅ Corrigido |
| GAP-ADMIN | Administradores online/busy não recebiam o toque inicial quando `include_administrators=true` — só apareciam no fallback offline; introduzido `recipients_base_scope` | ✅ Corrigido |
| BUG-QR-01 | `WavoipQrScanModal.cleanupSession` desconectava o SDK incondicionalmente, mesmo quando a sessão de QR nunca o usou — interrompia a conexão do `WavoipConnectionHost` | ✅ Corrigido |
| BUG-QR-02 | `startSession` marcava `qrRefreshError=true` quando status era `connecting` e QR ainda não estava pronto — estado de transição normal exibia mensagem de erro | ✅ Corrigido |
| BUG-QR-03 | `WavoipQrDisplay.showLoading` não cobria o estado `connecting` sem QR — tela ficava vazia em vez de exibir spinner de espera | ✅ Corrigido |
| BUG-WEBHOOK-01 | Payload live Wavoip usa `caller`/`receiver` em vez de `peer.phone` → `Skipped create: missing or inbox peer phone`; inbound sem `Call` nem broadcast | ✅ Corrigido (`PayloadNormalizer#contact_phone_from_caller_receiver`) |
| E2E-01 | Suite RSpec (`inbound_webhook_flow_spec`) + Playwright (`tests/e2e/wavoip`) + `bin/wavoip-pilot-verify` I2/O2 | ✅ Concluído |
