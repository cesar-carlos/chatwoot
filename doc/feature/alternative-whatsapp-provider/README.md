# Canal WhatsApp — Provider alternativo (API não oficial)

Análise para adicionar um gateway WhatsApp não-Meta (Evolution API, Baileys, WPPConnect, etc.) mantendo paridade máxima com o canal `Channel::Whatsapp` existente.

## Relacionado

- [WhatsApp Voice (Meta Calling)](../whatsapp-voice/README.md) — chamadas nativas; **não aplicável** a APIs não oficiais na maioria dos casos
- [NotificaMe WhatsApp](../notificame-whatsapp-integration/plano-geral.md) — plano prévio de terceiro provider no mesmo modelo

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) | Abstração atual, providers, webhooks |
| [unofficial-api-channel-feasibility.md](./unofficial-api-channel-feasibility.md) | Matriz de paridade, riscos, compliance |
| [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) | Arquitetura recomendada no fork |
| [twilio-vs-unofficial-vs-cloud.md](./twilio-vs-unofficial-vs-cloud.md) | Comparação das três abordagens |
| [effort-estimate-and-phases.md](./effort-estimate-and-phases.md) | Fases e estimativa de esforço |
| [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md) | Canal genérico de ligação WhatsApp via gateway não oficial |
| [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md) | Restrições Meta evitadas vs novas restrições do gateway |

## Resumo executivo

O Chatwoot **já tem um padrão de provider** em `Channel::Whatsapp` com dois valores: `default` (360dialog, BSP oficial) e `whatsapp_cloud` (Meta Graph API). A abstração cobre **envio** (texto, mídia, templates, interativos) via `Whatsapp::Providers::BaseService`, mas **recebimento** bifurca em dois parsers (`IncomingMessageService` vs `IncomingMessageWhatsappCloudService`) e várias features são **cloud-only**. APIs não oficiais exigem um **terceiro provider + adaptador de webhook** — viável para mensagens (MVP), difícil para paridade total, e **chamadas nativas WhatsApp quase certamente fora de escopo**.
