# Mapeamento de features: oficial → provider alternativo

Como cada capability do Chatwoot hoje (via Cloud API / 360dialog) se traduz para gateways não oficiais. Use como checklist de implementação por fase.

**Relacionados:** [gaps-and-blockers.md](./gaps-and-blockers.md) · [provider-comparison.md](./provider-comparison.md) · [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md)

---

## Legenda

| Símbolo | Significado |
|---------|-------------|
| ✅ | Reuso direto ou adapter simples |
| ⚠️ | Adapter não trivial ou parcial |
| ❌ | Não aplicável / não implementar no MVP |
| 🔧 | Exige mudança no fork (prepend/FORK) |

---

## Mensagens — outbound

| Feature Chatwoot | Implementação oficial | Provider alternativo | Componente a reusar |
|------------------|----------------------|----------------------|---------------------|
| Texto simples | `WhatsappCloudService#send_text_message` | REST send do gateway | `BaseService` + override `send_message` |
| Mídia (img/doc/audio/video) | Graph `/messages` + upload media | REST com URL ou base64 | `send_attachment_message` pattern do 360dialog |
| Voice note (PTT) | `voice: true` + opus | ⚠️ se gateway suportar áudio | Cloud-only hoje |
| Interativos (`input_select`) | `create_button/list_payload` | ⚠️ mapear items → API gateway | Helpers em `BaseService` |
| Templates | `send_template` + WABA sync | Texto livre ou lista local | `send_template` → texto ou noop |
| Reply/context | `whatsapp_reply_context` | ⚠️ `quoted` / `context` no gateway | Override no provider |
| CSAT survey | `CsatTemplateService` | ❌ | — |
| Campanhas one-off | `OneoffCampaignService` | ❌ | — |

---

## Mensagens — inbound

| Feature | Oficial | Alternativo | Serviço Chatwoot |
|---------|---------|-------------|------------------|
| Texto recebido | `IncomingMessageWhatsappCloudService` | Normalizer → flat | `IncomingMessageService` → `BaseService` |
| Mídia recebida | GET Graph media URL | Download URL/base64 gateway | `download_attachment_file` override |
| Status sent/delivered/read | `process_statuses` | Normalizer `statuses[]` | `IncomingMessageBaseService` |
| Dedup por `source_id` | Redis lock | Mesmo | `lock_message_source_id!` |
| Contato + conversa | `set_contact` / `set_conversation` | Mesmo após normalizar phone | `IncomingMessageBaseService` |
| Reply threading | `process_in_reply_to` | ⚠️ mapear `quotedMsg` | Base |
| Reações | Ignoradas | Possível ignorar | `unprocessable_message_type?` |
| SMB echoes | `smb_message_echoes` | ❌ | Cloud-only |
| Unsupported type | Placeholder message | Mesmo | `create_unsupported_message` |

---

## Templates e janela 24h

| Regra | Cloud API | Gateway | Ação no fork |
|-------|-----------|---------|--------------|
| Template fora de 24h | Obrigatório Meta | Não aplicável | 🔧 Bypass `MessageWindowService` |
| Sync templates inbox | Graph WABA | Lista local ou noop | `sync_templates` custom |
| UI seletor template | `message_templates` JSONB | Ocultar ou lista simplificada | Frontend capability |
| `SendOnWhatsappService` template force | `can_reply?` false | Desabilitar para gateway | 🔧 Prepend ou flag provider |

---

## Webhooks e transporte

| Aspecto | Cloud | Gateway |
|---------|-------|---------|
| Rota | `/webhooks/whatsapp/:phone` ou WABA payload | Mesma rota **ou** `/webhooks/gateway/:instance_id` |
| Verificação GET | Meta hub challenge | Token custom ou noop |
| Assinatura POST | HMAC `X-Hub-Signature-256` | API key header / shared secret |
| Formato | `entry/changes/value` | Proprietário → **Normalizer** |
| Job dispatch | `case provider` | 🔧 Prepend + normalize |
| Mutex contato | Redis por inbox+sender | Reusar após normalizar sender |

---

## Identificadores de contato

| Fonte | Formato | `ContactInbox#source_id` |
|-------|---------|--------------------------|
| Cloud API | `wa_id` / BSUID | Como recebido |
| 360dialog | `contacts[0].wa_id` | Como recebido |
| Evolution | `remoteJid` | Strip `@s.whatsapp.net` |
| Z-API | `phone` | E.164 sem `+` ou com — padronizar |
| LID / parent BSUID | Meta coexistence | `IncomingMessageIdentifierHelper` — avaliar se gateway envia |

**Regra:** normalizar no normalizer **uma vez**; manter consistência outbound/inbound.

---

## Frontend

| UI | Cloud | 360dialog | Gateway |
|----|-------|-----------|---------|
| Wizard setup | Embedded / manual | `?provider=360dialog` | 🔧 Card Evolution/Z-API |
| QR / conexão | OAuth Meta | — | Polling status + QR |
| Settings health | Meta health API | Parcial | Gateway status endpoint |
| Template picker | ✅ | ✅ | ❌ ou simplificado |
| Reply box restrictions | Cloud rules | Alguns bypass 360 | Capability-driven |
| Campanhas | ✅ | ❌ | ❌ |
| Botão ligar (voz) | EE Calling | ❌ | Canal separado |

---

## Voz (canal independente)

| Feature | Meta Cloud EE | Gateway |
|---------|---------------|---------|
| Inbound ring | `field=calls` webhook | Webhook proprietário se existir |
| Outbound | `POST /whatsapp_calls/initiate` + SDP | REST gateway + SDP se suportado |
| WebRTC | Browser ↔ Meta | Browser ↔ Gateway (provável) |
| `call_permission_request` | Obrigatório | ❌ |
| Modelo `Call` | `provider: whatsapp` | `provider: whatsapp_gateway` (fork) |
| UI | `useWhatsappCallSession` | `useGatewayCallSession` (fork) |

Voz é projeto separado. Ver [whatsapp-voice/README.md](../whatsapp-voice/README.md) e [whatsapp-voice/second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md).

---

## Enterprise vs OSS (mensagens)

| Feature | OSS | EE | Gateway fork |
|---------|-----|----|--------------|
| Envio texto/mídia | ✅ | ✅ | ✅ `custom/` |
| Incoming | ✅ | ✅ + calls intercept | ✅ normalizer |
| Chamadas | ❌ | ✅ cloud only | `custom/` separado |
| `channel_voice` flag | — | EE | Opcional fork |

---

## Fases × features (resumo)

| Fase | Features |
|------|----------|
| **0** | Registry, interfaces, prepend hooks, docs |
| **1** | Texto in/out, status básico, setup inbox, normalizer |
| **2** | Mídia, reply, bypass 24h (se desejado), `process_response` |
| **3** | Interativos, health/QR, observabilidade |
| **4** | Voz (só com contrato gateway documentado) |

---

## Matrizes por provider (fork)

| Provider | Documento específico |
|----------|---------------------|
| Evolution API (Node) | [evolution-api/feature-mapping.md](./evolution-api/feature-mapping.md) |
| Evolution Go | [evolution-go/feature-mapping.md](./evolution-go/feature-mapping.md) |
