# Changelog de refatoração — Wavoip

Resumo condensado de todo o trabalho de correção/qualidade já concluído na implementação
Wavoip. Para o texto completo (descrição, código antes/depois, racional) de cada item, veja
[archive/](./archive/) — mantido só como referência histórica.

## 26 jun. – 03 jul. 2026 — revisão inicial (32/32 concluído)

Revisão de código cobrindo toda a implementação `custom/**/wavoip/**` das fases 1–4.
Suite de regressão: 104 RSpec + 83 Vitest.

| ID | Título | Severidade | Status |
|----|--------|------------|--------|
| BUG-01 | Deadlock em `acceptIncomingCall` (offer removida antes de chegar) | Alta | ✅ |
| BUG-02 | Alertas de chamada hardcoded em inglês | Média | ✅ |
| BUG-03 | Múltiplos `EscalateRingJob` por retransmissão de webhook | Média | ✅ |
| BUG-04 | `isConnecting` falso prematuro em conexões concorrentes | Baixa | ✅ |
| BUG-05 | `activeInboxId` não limpo ao cancelar outbound | Baixa | ✅ |
| BUG-06 | Botão "Acordar dispositivo" não chamava `device.wakeUp()` | Média | ✅ |
| GAP-OUTBOUND-01 | Widget outbound sumia com SDK ainda tocando | Alta | ✅ |
| GAP-01 | `offline_fallback: 'none'` não bloqueava escalação | Alta | ✅ |
| GAP-02 | `accepted_by_agent_id` sem retry | Alta | ✅ alerta UI em todos os flush paths |
| GAP-03 | Token rotacionado não reconectava SDK | Média | ✅ |
| GAP-04 | `PhoneNormalizer` assume Brasil | Média | ✅ prefixos LATAM + specs MX/CL |
| GAP-05 | `ring_timeout_seconds` sem limite máximo | Baixa | ✅ |
| GAP-06 | Listener `statusChanged` podia vazar | Baixa | ✅ |
| GAP-07 | `assignee` ≡ `assignee_or_inbox_members` | Baixa | ✅ |
| GAP-08 | `notify_busy_agents` não valia na escalação | Baixa | ✅ |
| GAP-09 | Toggle admins sem contrato no backend | Baixa | ✅ |
| GAP-10 | `saveCallRouting` com race last-write-wins | Baixa | ✅ |
| GAP-11 | Polling mesmo com device já conectado | Baixa | ✅ |
| GAP-ADMIN | Admins online não recebiam toque inicial | Alta | ✅ |
| QC-01 a QC-14 | Duplicações, N+1, memory leaks, código morto (ver [archive/code-quality.md](./archive/code-quality.md)) | Média/Baixa | ✅ |

## 04 jul. 2026 — incidentes de produção corrigidos no dia

Encontrados e corrigidos na mesma sessão a partir de testes reais em produção (não fazem
parte da revisão de 26 jun.):

| Problema | Causa | Correção |
|----------|-------|----------|
| Notificação de "chamada recebida" disparando quando o **agente** iniciava uma ligação | SDK emite `offer` também para chamadas outbound; código tratava todo `offer` como inbound | `wavoipOutboundGuard.js` — ignora offer/cable quando o agente é quem iniciou |
| Conversa não reabria como `pending` ao receber ligação | `ConversationReopenService` só reabria como `open`; sem status dedicado para inbound | `status:` parametrizado (`pending` inbound / `open` outbound) + `wavoipInboundConversation.js` |
| Widgets fantasma de chamadas antigas em `ringing` reaparecendo | Nenhuma rede de segurança fechava calls presas quando o webhook de término nunca chegava | `Wavoip::Calls::StaleCallTimeoutScheduler` + `Wavoip::AutoNoAnswerRingJob` (backend) e `isStaleWavoipRingingMessage` (frontend, filtro de 3 min) |
| Gravação nunca aparecia no histórico | Conta não tinha o webhook `RECORD` habilitado no painel Wavoip | `Wavoip::Calls::DirectRecordingUrl` + `Wavoip::FetchDirectRecordingJob` — fallback via URL direta documentada (`storage.wavoip.com/{id}`) |
| "Ligar de volta" falhava com mensagem genérica | Sem checagem de dispositivo restrito/lotado; erro de conexão sem tradução | `wavoipOutboundPreflight.js` (checagem compartilhada com o botão do painel de contato) + mensagem `CONNECT_FAILED` |
| Webhook da Wavoip parou de entregar eventos silenciosamente | 502 transitório durante deploy — Wavoip não retentou nem voltou sozinho | Ver [operations-runbook.md](../operations-runbook.md#webhook-parou-de-chegar-sem-aviso) — requer reativação manual no painel Wavoip |

## 04 jul. 2026 — segunda rodada (auditoria de confiabilidade)

Ver commits/specs do dia para detalhes. Resumo: lock atômico em schedulers, `CallFinalizer`
extraído para eliminar duplicação de "finalizar chamada" em 4 lugares, `DirectionInferrer`
extraído do `PayloadNormalizer`, correções de memory leak e reconciliação de IDs no frontend.
Detalhes completos no PR/diff correspondente.
