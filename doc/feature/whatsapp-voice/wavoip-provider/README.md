# Wavoip — Estratégia de implementação (provider alternativo de voz)

Plano para integrar **[Wavoip](https://wavoip.gitbook.io/api)** como primeiro provider alternativo de **chamadas de voz WhatsApp in-app** no fork Chatwoot, sem alterar o caminho upstream **Meta Cloud Calling**.

**Última revisão:** jun/2026 (alinhado à reavaliação arquitetural global).

> **Dúvidas durante a implementação?** Consulte primeiro [official-docs.md](./official-docs.md) — índice completo da documentação oficial Wavoip mapeado por fase e módulo Chatwoot.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Contratos, portas, inversão de dependência** | [contracts-and-ports.md](./contracts-and-ports.md) — **ler antes de codar** |
| **Documentação oficial Wavoip (índice)** | [official-docs.md](./official-docs.md) |
| **Decisão go/no-go e posicionamento vs Meta** | [wavoip-vs-meta.md](./wavoip-vs-meta.md) |
| **Criação da caixa de entrada (formulário completo)** | [inbox-setup.md](./inbox-setup.md) |
| **Arquitetura, limites de classes, fluxos** | [architecture.md](./architecture.md) |
| **Fases, entregas, critérios de done** | [implementation-plan.md](./implementation-plan.md) — **plano mestre** (Trilhas A–C + master checklist) |
| **SDK browser, notificações, bolha** | [frontend-integration.md](./frontend-integration.md) |
| **Referência `@wavoip/wavoip-api`** | [sdk-reference.md](./sdk-reference.md) |
| **Auth webhook, ActionCable, idempotência** | [webhook-contract.md](./webhook-contract.md) |
| **Suporte / troubleshooting admin** | [operations-runbook.md](./operations-runbook.md) |
| **Spike Fase 0** | [spike-notes.template.md](./spike-notes.template.md) · [fixtures/](./fixtures/) |

**Contexto upstream:** [../README.md](../README.md) · [../second-provider-strategy.md](../second-provider-strategy.md) · [../architecture-and-flow.md §13](../architecture-and-flow.md#13-roadmap-de-refatoração-melhorias-sugeridas)

---

## Pré-requisito fork (antes da Fase 1 Wavoip)

Executar **Fase 0 FE** de [second-provider-strategy.md §Fase 0](../second-provider-strategy.md#fase-0--refactor-pré-requisito-recomendado):

| Entrega | Por quê |
|---------|---------|
| `useWebRtcCallSession(callsAPI)` extraído | Wavoip não duplica 456 linhas de WebRTC Meta |
| `WEBRTC_PROVIDERS` + registry em `useCallSession` | `endCall` / `joinCall` funcionam para `wavoip` |
| `actionCable.js` generalizado | Eventos `voice_call.*` do webhook Wavoip chegam ao widget |

**Não** é necessário o refactor backend Meta (adapter/builders) para Wavoip — canal `Channel::Wavoip` é separado. **É obrigatório** o registry FE.

---

## Resumo executivo

Wavoip **não** é CPaaS Meta. É **SDK browser** + **webhooks HTTP** para CRM.

| Camada | Responsável |
|--------|-------------|
| **Dispositivo + mídia** | Browser ↔ Wavoip (`Device.status === 'open'` obrigatório) |
| **Histórico CRM** | Rails webhook + `Call` + bolha `voice_call` |
| **UI** | `FloatingCallWidget` + composables em `custom/` |

---

## Melhorias incorporadas (jun/2026)

| Área | Melhoria |
|------|----------|
| **Registry** | Depende de Fase 0 FE global — ver [contracts-and-ports.md §5](./contracts-and-ports.md#5-contratos-frontend-javascript) |
| **Portas backend** | DTO + handlers injetados — [contracts-and-ports.md §4](./contracts-and-ports.md#4-contratos-backend-ruby) |
| **Webhook** | Auth fixa, idempotência, rate limit — [webhook-contract.md](./webhook-contract.md) |
| **ActionCable** | Contrato Wavoip sem SDP; ignora `outbound_connected` |
| **Bolha** | `VoiceCall.vue` sem join SDP; gravação via `record_url` |
| **Fases** | Push offline na Fase 3; gravação isolada na Fase 4 |
| **Spike** | Template + fixtures JSON + smoke `InboundCallBuilder` |
| **Ops** | Runbook + checklist onboarding semáforo |
| **Rollout** | Flag `channel_wavoip` em `custom/config/features.yml` |
| **Segurança** | Token mascarado na API; logs sem payload em produção |

---

## Escopo por fase

Plano detalhado com IDs rastreáveis (G1–G8, W-P0, W-B/F/O, M-P1/P2): **[implementation-plan.md](./implementation-plan.md)**.

| Trilha / Fase | Entrega | Duração |
|---------------|---------|---------|
| **A — Pré-Fase 0** | Registry FE + portas BE + Vite | ~1–1,5 sem |
| **B.0 — Spike** | Áudio + webhook + fixtures reais | 2–4 dias |
| **B.1 — Fundação** | Canal + webhook + device panel | ~1–1,5 sem |
| **B.2 — Outbound** | `startCall` + handlers + facade | ~1 sem |
| **B.3 — Inbound** | Ring + PATCH agent + push offline | 1–1,5 sem |
| **B.4 — Gravação** | `RECORD` webhook + bolha | 3–5 dias |
| **B.5 — Diagnóstico** | Opcional | 3–5 dias |
| **C — Meta P1–P2** | Adapter, builders, permission (paralelo) | 2–3 sem |

**MVP Wavoip (A + B.0–B.3):** ~5–6 semanas.

---

## Gates de produto

**Tile Wavoip:** `channel_voice` (+ `channel_wavoip` em piloto).

**Ligar / aceitar:** token + device `open` + agente online + gesto do usuário.

**Backlog e execução:** [contracts-and-ports.md §12](./contracts-and-ports.md#12-melhorias-pendentes-backlog) · [implementation-plan.md](./implementation-plan.md) master checklist.

---

## Índice completo

| Arquivo | Conteúdo |
|---------|----------|
| [contracts-and-ports.md](./contracts-and-ports.md) | **Portas, DTOs, DI, fontes da verdade, anti god class** |
| [official-docs.md](./official-docs.md) | **Índice doc oficial Wavoip** — consulta durante implementação |
| [wavoip-vs-meta.md](./wavoip-vs-meta.md) | Wavoip ≠ stack Meta |
| [inbox-setup.md](./inbox-setup.md) | Wizard caixa de entrada |
| [architecture.md](./architecture.md) | Módulos, fluxos, mapa `custom/` |
| [implementation-plan.md](./implementation-plan.md) | Fases, FORK inventory, testes |
| [frontend-integration.md](./frontend-integration.md) | SDK, registry, bolha |
| [sdk-reference.md](./sdk-reference.md) | Device, Calls, Types |
| [webhook-contract.md](./webhook-contract.md) | Auth, idempotência, ActionCable |
| [operations-runbook.md](./operations-runbook.md) | Troubleshooting admin |
| [spike-notes.template.md](./spike-notes.template.md) | Template Fase 0 |
| [feature-flags.md](./feature-flags.md) | Flag `channel_wavoip` para piloto |
| [fixtures/](./fixtures/) | JSON de referência para specs |
