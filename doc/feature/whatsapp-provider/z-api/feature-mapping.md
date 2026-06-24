# Mapeamento de features — `zapi` no Chatwoot

Checklist feature a feature. Complementa [../feature-mapping.md](../feature-mapping.md).

**Legenda:** ✅ adapter simples · ⚠️ não trivial · ❌ N/A MVP · 🔧 prepend/FORK

---

## Mensagens — outbound

| Feature Chatwoot | API Z-API | Fase | Componente |
|------------------|-------------|------|------------|
| Texto | `POST .../send-text` | 1 | `ZapiService#send_message` |
| Mídia imagem | `POST .../send-image` | 2 | `send_attachment_message` |
| Áudio | `POST .../send-audio` | 2 | idem |
| Vídeo | `POST .../send-video` | 2 | idem |
| Documento | `POST .../send-document/{ext}` | 2 | idem |
| Sticker / GIF / PTV | `send-sticker`, `send-gif`, `send-ptv` | 3 | — |
| Location | `POST .../send-location` | 3 | — |
| Contact card | `POST .../send-contact` | 3 | share-contact projeto |
| Templates WABA | — | ❌ | Z-API não expõe templates Meta |
| Reply/quote | `messageId` opcional em `POST .../send-text` | 2 | mesmo endpoint send |
| Botões / listas | `send-button-*`, `send-option-list` | 3 | sem paridade CW UI |
| `source_id` | `messageId` na response | 1 | `process_response` |
| Typing | — | ❌ | presence via chat-presence webhook only |
| Mark read | `POST .../read-message` | 2 | ao abrir conversa |

---

## Mensagens — inbound

| Feature | Evento Z-API | Fase | Componente |
|---------|--------------|------|------------|
| Texto | `ReceivedCallback` + `text.message` | 1 | `ZapiNormalizer` |
| Imagem | `ReceivedCallback` + `image.imageUrl` | 2 | download URL |
| Áudio / vídeo / doc | `audio`, `video`, `document` keys | 2 | download URL |
| Status read | `MessageStatusCallback` READ | 1 | → `statuses[]` |
| Delivery | `DeliveryCallback` | 1 | opcional / erro log |
| Dedup | — | 1 | `lock_message_source_id!` |
| Contato/conversa | `phone`, `senderName` | 1 | `IncomingMessageBaseService` |
| Reply threading | `referenceMessageId` se presente | 2 | `process_in_reply_to` |
| Reações | `reaction` no payload | 3 | ignorar MVP |
| Grupos | `isGroup: true` | ❌ MVP | filtrar |
| Canais | `isNewsletter: true` | ❌ MVP | filtrar |
| Echo fromMe | `fromMe: true` | 1 | filtrar + `notifySentByMe: false` |

---

## Templates e janela 24h

| Regra | Ação fork |
|-------|-----------|
| Janela 24h Meta | 🔧 `MessageWindowService` → `nil` |
| Templates Meta | `sync_templates` noop |
| UI template picker | ocultar para `zapi` |
| `send_template` | não aplicável |

---

## Webhooks

| Aspecto | Z-API | Chatwoot |
|---------|-------|----------|
| Config | 4–7 URLs ou 1 bulk | 1 rota multiplexada |
| Auth | HTTPS obrigatório | `?token=webhook_token` |
| Demux | campo `type` | `ZapiNormalizer` router |
| Mídia | URL no payload | download no job |

---

## Conexão / wizard

| Feature | API | Fase |
|---------|-----|------|
| Status | `GET .../status` | 1 |
| QR imagem | `GET .../qr-code/image` | 1 |
| Pairing phone | `GET .../phone-code/{phone}` | 2 |
| Disconnect | `GET .../disconnect` | 1 |
| Connected event | `ConnectedCallback` | 1 | `ConnectionEvents#handle_connected` — phone_number sync + AC broadcast |
| Partners create | `POST /instances/integrator/on-demand` | 2 |

---

## Contatos e sync

| Feature | API | Fase |
|---------|-----|------|
| Listar contatos | `GET .../contacts` | 2 |
| Validar número | `GET .../phone-exists/{phone}` | 2 |
| Import histórico | — | ❌ | sem equivalente confiável MVP |

---

## Fora de escopo

| Feature Z-API | Motivo |
|---------------|--------|
| Grupos / comunidades | Chatwoot não modela |
| Newsletter / Status stories | Fora do produto |
| Chamadas (`Calls`) | Projeto voz separado |
| WhatsApp Business catálogo | Fase futura |
| Mobile onboarding | Complexidade alta |
| Meta AI | Irrelevante para inbox |
