# WhatsApp Providers

Esta pasta consolida análise e decisões para usar **WhatsApp sem a Cloud API / WABA oficial** da Meta — por exemplo via NotificaMe, Evolution API ou outro gateway com sessão de cliente.

O objetivo é contrastar expectativas ("sem restrições WhatsApp") com **restrições reais evitadas, restrições que permanecem e novas restrições** do provider não oficial, inclusive para um **canal genérico de ligação**.

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md) | **Canal genérico de chamadas** via API não oficial — UI, 3 opções de arquitetura, reuso, fases, riscos |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Comparação honesta: restrições Meta evitadas vs riscos e limites do gateway não oficial; impacto em voz |

## Relação com outras áreas

| Área | Documento |
|------|-----------|
| Integração NotificaMe (mensagens) | [notificame-whatsapp-integration/plano-geral.md](../notificame-whatsapp-integration/plano-geral.md) |
| Voz WhatsApp oficial (Meta Calling API) | [whatsapp-voice/README.md](../whatsapp-voice/README.md) |
| Segundo provider de **chamadas** (se SDP disponível) | [whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Twilio PSTN vs WhatsApp nativo | [whatsapp-voice/twilio-vs-whatsapp-native.md](../whatsapp-voice/twilio-vs-whatsapp-native.md) |

## Visão geral

- **Mensagens:** provider alternativo em `Channel::Whatsapp` remove gates da Cloud API (templates, janela 24h, WABA), mas **não** remove risco de ban nem instabilidade de sessão.
- **Voz:** abandonar a API oficial **não garante** ligações no dashboard — o modelo de call depende do gateway; ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) §4.
