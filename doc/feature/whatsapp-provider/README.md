# WhatsApp Provider — Documentação

Esta pasta consolida análise e decisões para integrar **providers WhatsApp alternativos** (Evolution API, Z-API, NotificaMe, gateways Baileys) no fork Chatwoot — em contraste com a **Cloud API / WABA oficial** da Meta.

Objetivo: orientar implementadores sobre **o que reusar**, **onde o código bloqueia**, **como adaptar com merge-safety** (`custom/`, `prepend_mod_with`, `# FORK:`) e **o que muda** ao abandonar a API oficial.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementador novo** | [implementation-decision-tree.md](./implementation-decision-tree.md) → [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) |
| **Revisão técnica do código atual** | [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) → [gaps-and-blockers.md](./gaps-and-blockers.md) |
| **Escolha de gateway** | [provider-comparison.md](./provider-comparison.md) |
| **Checklist feature a feature** | [feature-mapping.md](./feature-mapping.md) |

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Estado atual no código: providers, webhooks, incoming, frontend, extension points |
| [gaps-and-blockers.md](./gaps-and-blockers.md) | **Lacunas que bloqueiam** providers alternativos + mitigações |
| [feature-mapping.md](./feature-mapping.md) | Mapeamento feature oficial → implementação gateway |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Árvore de decisão, fases, o que reusar vs criar |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Plano concreto, fases, critérios de done e estratégia de fork |
| [provider-comparison.md](./provider-comparison.md) | Evolution API, Z-API, Baileys genérico, NotificaMe |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Restrições Meta evitadas vs riscos do gateway; impacto em voz |

---

## Relação com outras áreas

| Área | Documento |
|------|-----------|
| Integração NotificaMe (mensagens) | [notificame-whatsapp-integration/plano-geral.md](../notificame-whatsapp-integration/plano-geral.md) |
| Voz WhatsApp oficial (Meta Calling API) | [whatsapp-voice/README.md](../whatsapp-voice/README.md) |
| Segundo provider de **chamadas** (se SDP disponível) | [whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Twilio PSTN vs WhatsApp nativo | [whatsapp-voice/twilio-vs-whatsapp-native.md](../whatsapp-voice/twilio-vs-whatsapp-native.md) |
| Disciplina de branch e merge (fork) | [fork-strategy.mdc](../../../.cursor/rules/fork-strategy.mdc) · [fork-merge-conflicts.mdc](../../../.cursor/rules/fork-merge-conflicts.mdc) |
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

- `PROVIDERS` whitelist bloqueia novos providers
- `provider_service` envia tudo que não é cloud para 360dialog
- `MessageWindowService` força janela 24h em **todo** `Channel::Whatsapp`
- Frontend só distingue `whatsapp_cloud` vs `default`

Detalhes: [gaps-and-blockers.md](./gaps-and-blockers.md).

### Restrições que desaparecem (e as que não desaparecem)

- **Somem na API:** templates WABA, janela 24h Meta, embedded signup, Calling API enrollment
- **Permanecem:** ToS WhatsApp, risco de ban, sessão/QR, compliance LGPD
- **Chatwoot ainda pode impor:** janela 24h e templates via `SendOnWhatsappService` — bypass necessário no fork

Ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md).

---

*Última atualização: jun/2026 — reanálise código + providers Evolution/Z-API.*
