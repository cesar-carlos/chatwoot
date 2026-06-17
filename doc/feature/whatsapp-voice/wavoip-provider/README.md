# Wavoip — Estratégia de implementação (provider alternativo de voz)

Plano para integrar **[Wavoip](https://wavoip.gitbook.io/api)** como primeiro provider alternativo de **chamadas de voz WhatsApp in-app** no fork Chatwoot, sem alterar o caminho upstream **Meta Cloud Calling**.

**Última revisão:** jun/2026.

> **Dúvidas durante a implementação?** Consulte primeiro [official-docs.md](./official-docs.md) — índice completo da documentação oficial Wavoip mapeado por fase e módulo Chatwoot.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Documentação oficial Wavoip (índice)** | [official-docs.md](./official-docs.md) |
| **Decisão go/no-go e posicionamento vs Meta** | [wavoip-vs-meta.md](./wavoip-vs-meta.md) |
| **Criação da caixa de entrada (formulário completo)** | [inbox-setup.md](./inbox-setup.md) |
| **Arquitetura, limites de classes, fluxos** | [architecture.md](./architecture.md) |
| **Fases, entregas, critérios de done** | [implementation-plan.md](./implementation-plan.md) |
| **SDK browser, notificações, bolha** | [frontend-integration.md](./frontend-integration.md) |
| **Referência `@wavoip/wavoip-api`** | [sdk-reference.md](./sdk-reference.md) |
| **Auth webhook, ActionCable, idempotência** | [webhook-contract.md](./webhook-contract.md) |
| **Suporte / troubleshooting admin** | [operations-runbook.md](./operations-runbook.md) |
| **Spike Fase 0** | [spike-notes.template.md](./spike-notes.template.md) · [fixtures/](./fixtures/) |

**Contexto upstream:** [../README.md](../README.md) · [../second-provider-strategy.md](../second-provider-strategy.md)

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
| **FORK** | Registry `browserVoiceProviders` + `voiceCallCableRegistry` — ≤ 8 arquivos upstream |
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

| Fase | Entrega | Duração |
|------|---------|---------|
| **0** | Spike + fixtures + smoke EE | 2–4 dias |
| **1** | Canal + webhook skeleton + device panel + checklist | 1–1,5 sem |
| **2** | Outbound + handlers + gates SDK | ~1 sem |
| **3** | Inbound + widget + push offline | 1–1,5 sem |
| **4** | Gravação | 3–5 dias |
| **5** | Diagnóstico + mídia (opcional) | 3–5 dias |

Detalhes: [implementation-plan.md](./implementation-plan.md).

---

## Gates de produto

**Tile Wavoip:** `channel_voice` (+ `channel_wavoip` em piloto).

**Ligar / aceitar:** token + device `open` + agente online + gesto do usuário.

---

## Índice completo

| Arquivo | Conteúdo |
|---------|----------|
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
