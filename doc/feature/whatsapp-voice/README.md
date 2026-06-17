# WhatsApp Voice / Calling — Documentação de análise

Esta pasta consolida a análise técnica do suporte a **chamadas de voz WhatsApp** no Chatwoot Enterprise (WhatsApp Cloud Calling API + WebRTC browser↔Meta). O objetivo é orientar implementação, extensão com um segundo provider de chamadas WhatsApp e decisões de arquitetura no fork.

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [architecture-and-flow.md](./architecture-and-flow.md) | Fluxo completo: setup, inbound, outbound, Meta API, frontend, gates Enterprise |
| [provider-coupling-and-extensibility.md](./provider-coupling-and-extensibility.md) | Acoplamento atual, padrão Twilio vs WhatsApp, viabilidade de novo provider |
| [twilio-vs-whatsapp-native.md](./twilio-vs-whatsapp-native.md) | O que se perde ao usar stack Twilio em vez de WhatsApp Cloud Calling |
| [second-provider-strategy.md](./second-provider-strategy.md) | Recomendação concreta para adicionar um segundo provider de chamadas WhatsApp |

## Visão geral

O recurso permite que agentes **atendam e façam chamadas de voz pelo WhatsApp** diretamente no dashboard. O Chatwoot atua como **orquestrador de sinalização e estado** (SDP, `Call`, mensagens `voice_call`, ActionCable); a **mídia de áudio** trafega **diretamente entre o navegador do agente e a Meta** via WebRTC — não passa pelo servidor Chatwoot. Requer **Enterprise Edition**, feature flag `channel_voice`, inbox com provider `whatsapp_cloud` e número inscrito na WhatsApp Business Calling API. Existe um canal de voz **Twilio** separado (`Channel::TwilioSms` + `voice_enabled`), que implementa **PSTN/conferência** e **não substitui** chamadas nativas WhatsApp.
