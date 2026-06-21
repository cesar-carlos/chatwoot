# WhatsApp Provider — Documentação

Esta pasta consolida análise e decisões para integrar **providers WhatsApp alternativos** (Evolution API, Z-API, NotificaMe, gateways Baileys) no fork Chatwoot — em contraste com a **Cloud API / WABA oficial** da Meta.

Objetivo: orientar implementadores sobre **o que reusar**, **onde o código bloqueia**, **como adaptar com merge-safety** (`custom/`, `prepend_mod_with`, `# FORK:`) e **o que muda** ao abandonar a API oficial.

**Status código + docs:** [STATUS.md](./STATUS.md)

---

## Estado dos providers (jun/2026)

| Provider | Documentação | Código fork |
|----------|--------------|-------------|
| **Evolution API** (`evolution`) | [evolution-api/](./evolution-api/) | ✅ Fase 0–3 em `custom/` |
| **Evolution Go** (`evolution_go`) | [evolution-go/](./evolution-go/) | ❌ planejamento |
| Z-API, NotificaMe | comparação / pasta NotificaMe | ❌ |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementador novo** | [implementation-decision-tree.md](./implementation-decision-tree.md) → [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) |
| **Revisão técnica do código atual** | [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) → [gaps-and-blockers.md](./gaps-and-blockers.md) |
| **Escolha de gateway** | [provider-comparison.md](./provider-comparison.md) |
| **Provider Evolution API (piloto Node)** | [evolution-api/README.md](./evolution-api/README.md) → [evolution-api/implementation-plan.md](./evolution-api/implementation-plan.md) |
| **Provider Evolution Go** | [evolution-go/README.md](./evolution-go/README.md) → [evolution-go/gaps-and-improvements.md](./evolution-go/gaps-and-improvements.md) |
| **Checklist feature a feature** | [feature-mapping.md](./feature-mapping.md) |

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [STATUS.md](./STATUS.md) | **Revisão consolidada** — código vs documentação por provider |
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Estado atual no código: providers, webhooks, incoming, frontend, extension points |
| [gaps-and-blockers.md](./gaps-and-blockers.md) | **Lacunas que bloqueiam** providers alternativos + mitigações |
| [feature-mapping.md](./feature-mapping.md) | Mapeamento feature oficial → implementação gateway |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Árvore de decisão, fases, o que reusar vs criar |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Plano concreto, fases, critérios de done e estratégia de fork |
| [provider-comparison.md](./provider-comparison.md) | Evolution API, Z-API, Baileys genérico, NotificaMe |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Restrições Meta evitadas vs riscos do gateway; impacto em voz |
| [evolution-api/](./evolution-api/) | **Evolution API (Node/Baileys):** integração atual, APIs, webhooks, regras de negócio, plano de fases |
| [evolution-go/](./evolution-go/) | **Evolution Go (whatsmeow):** planejamento — [implementation-readiness.md](./evolution-go/implementation-readiness.md), [gaps-and-improvements.md](./evolution-go/gaps-and-improvements.md) |

---

## Relação com outras áreas

| Área | Documento |
|------|-----------|
| Integração NotificaMe (mensagens) | [notificame-whatsapp-integration/plano-geral.md](../notificame-whatsapp-integration/plano-geral.md) |
| Voz WhatsApp oficial (Meta Calling API) | [whatsapp-voice/README.md](../whatsapp-voice/README.md) |
| Segundo provider de **chamadas** (se SDP disponível) | [whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Twilio PSTN vs WhatsApp nativo | [whatsapp-voice/twilio-vs-whatsapp-native.md](../whatsapp-voice/twilio-vs-whatsapp-native.md) |
| Disciplina de branch e merge (fork) | [fork-workflow.mdc](../../../.cursor/rules/fork-workflow.mdc) |
| Inventário de divergências FORK | `bin/fork-inventory` → `doc/fork-divergences.txt` |

---

## Visão geral (jun/2026)

### Recomendação arquitetural

1. **Mensagens:** estender `Channel::Whatsapp` com novo `provider` (padrão 360dialog), código em `custom/`, **normalizer de webhook** → payload flat → `IncomingMessageService`.
2. **Voz:** canal **independente** para gateways (`Channel::WhatsappCallGateway` / tile `whatsapp_call_gateway`); Meta oficial usa `Channel::Whatsapp` + tile `whatsapp_call` — ver [whatsapp-voice/README.md](../whatsapp-voice/README.md).
3. **Referência de contrato:** `WhatsappCloudService` + `IncomingMessageWhatsappCloudService` (oficial); `Whatsapp360DialogService` (segundo provider no mesmo model).
4. **Não editar** serviços cloud existentes — adapters finos em `custom/`.
5. **Whitelist de provider:** exige edição mínima com `# FORK:` em `Channel::Whatsapp::PROVIDERS`; prepend sozinho não altera a validação já carregada.

### Extension points principais

| # | Ponto | Mecanismo |
|---|-------|-----------|
| 1 | Whitelist de provider | `# FORK:` mínimo em `PROVIDERS` |
| 2 | Webhook incoming | `Webhooks::WhatsappEventsJob.prepend` + `GatewayNormalizer` |
| 3 | Dispatch de provider | `Channel::Whatsapp.prepend` + `MessagingProvider::Registry` |
| 4 | Regras 24h/templates | `MessageWindowService.prepend` + capability por provider |

### Principais lacunas no código

- ✅ Mitigado para **`evolution`**: registry, prepends, webhook dedicado, bypass 24h
- ❌ `evolution_go`, `zapi`, `notificame` ainda fora de `PROVIDERS`
- ⚠️ Upstream ainda envia non-cloud → 360dialog **sem** prepend (gateways precisam registry)

Detalhes: [gaps-and-blockers.md](./gaps-and-blockers.md) · [STATUS.md](./STATUS.md).

### Restrições que desaparecem (e as que não desaparecem)

- **Somem na API:** templates WABA, janela 24h Meta, embedded signup, Calling API enrollment
- **Permanecem:** ToS WhatsApp, risco de ban, sessão/QR, compliance LGPD
- **Chatwoot ainda pode impor:** janela 24h e templates via `SendOnWhatsappService` — bypass necessário no fork

Ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md).

---

*Última atualização: jun/2026 — Evolution Node em código; Evolution Go documentado; ver [STATUS.md](./STATUS.md).*
