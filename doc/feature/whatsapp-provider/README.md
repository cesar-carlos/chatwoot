# WhatsApp Provider — Documentação

Esta pasta consolida análise e decisões para usar **WhatsApp sem a Cloud API / WABA oficial** da Meta — por exemplo via NotificaMe, Evolution API ou outro gateway com sessão de cliente.

O objetivo é contrastar expectativas ("sem restrições WhatsApp") com **restrições reais evitadas, restrições que permanecem e novas restrições** do provider não oficial, inclusive **dois canais independentes** (mensagens + chamadas) com registries de provider extensíveis.

## Índice

| Documento | Conteúdo |
|-----------|----------|
| **[dual-channel-provider-architecture.md](./dual-channel-provider-architecture.md)** | **Documento mestre** — arquitetura dual-channel (mensagens + voz), interfaces `MessagingProvider` / `CallProvider`, fork merge-safe, fases |
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Estado atual: providers, webhooks, incoming, frontend setup |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Plano concreto: estender `Channel::Whatsapp` com gateway (Evolution) |
| [effort-estimate-and-phases.md](./effort-estimate-and-phases.md) | Cronograma e critérios de done por fase |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Comparação honesta: restrições Meta evitadas vs riscos do gateway; impacto em voz |
| [unofficial-api-channel-feasibility.md](./unofficial-api-channel-feasibility.md) | Viabilidade técnica do canal não oficial |
| [twilio-vs-unofficial-vs-cloud.md](./twilio-vs-unofficial-vs-cloud.md) | Twilio PSTN vs Cloud vs gateway |
| [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md) | Canal genérico de **chamadas** via API não oficial — UI, opções de arquitetura, reuso |

## Relação com outras áreas

| Área | Documento |
|------|-----------|
| Integração NotificaMe (mensagens) | [notificame-whatsapp-integration/plano-geral.md](../notificame-whatsapp-integration/plano-geral.md) |
| Voz WhatsApp oficial (Meta Calling API) | [whatsapp-voice/README.md](../whatsapp-voice/README.md) |
| Acoplamento e extensibilidade de voz | [whatsapp-voice/provider-coupling-and-extensibility.md](../whatsapp-voice/provider-coupling-and-extensibility.md) |
| Segundo provider de **chamadas** (se SDP disponível) | [whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Twilio PSTN vs WhatsApp nativo | [whatsapp-voice/twilio-vs-whatsapp-native.md](../whatsapp-voice/twilio-vs-whatsapp-native.md) |
| Disciplina de branch e merge (fork) | [fork-strategy.mdc](../../.cursor/rules/fork-strategy.mdc) · [fork-merge-conflicts.mdc](../../.cursor/rules/fork-merge-conflicts.mdc) |
| Inventário de divergências FORK | `bin/fork-inventory` → `doc/fork-divergences.txt` |

## Visão geral

- **Dois canais independentes:** mensagens (`whatsapp`) e chamadas (`whatsapp_call` / gateway) — ver [dual-channel-provider-architecture.md](./dual-channel-provider-architecture.md).
- **Mensagens:** provider alternativo em `Channel::Whatsapp` remove gates da Cloud API (templates, janela 24h, WABA), mas **não** remove risco de ban nem instabilidade de sessão.
- **Voz:** abandonar a API oficial **não garante** ligações no dashboard — o modelo de call depende do gateway; ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) §4 e [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md).
- **Implementações oficiais Meta** são o **template de contrato** para adapters alternativos (`WhatsappCloudService`, `useWhatsappCallSession`).
