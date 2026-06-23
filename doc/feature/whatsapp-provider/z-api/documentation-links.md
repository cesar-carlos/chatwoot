# Links de documentação — Z-API

Índice alinhado à collection **[Z-API Collection](https://go.postman.co/collection/1696280-cea57506-b9de-4e61-b4d5-227743bd8151)** (oficial) e ao fork **[Cesar Carlos](https://go.postman.co/collection/9985534-cdcfbd61-4ce9-451d-80a8-fe3c5cd6da6d)**.

**Base URL API:** `https://api.z-api.io`

**Doc oficial:** https://developer.z-api.io/

**Manutenção:** índice máquina oficial em https://developer.z-api.io/llms.txt

**Variáveis da collection:**

| Variável | Uso |
|----------|-----|
| `BASE_URL` | `https://api.z-api.io` |
| `INSTANCE_ID` | ID da instância no painel Z-API |
| `INSTANCE_TOKEN` | Token da instância (no path da URL) |
| `CLIENT_TOKEN` | Header `Client-Token` (segurança da conta) |
| `PARTNER_AUTH_TOKEN` | Bearer para API Partners (`/instances/integrator/*`) |

**Padrão de URL:** `{{BASE_URL}}/instances/{{INSTANCE_ID}}/token/{{INSTANCE_TOKEN}}/{ação}`

**Auth:** header `Client-Token: {{CLIENT_TOKEN}}` em todas as rotas de instância.

---

## Postman → endpoints por pasta (Chatwoot)

Legenda **Fase fork:** **1** = MVP · **2** = pós-MVP · **—** = fora de escopo inicial

### Instance

| Operação Postman | Método | Path | Fase fork |
|------------------|--------|------|-----------|
| Status da instância | `GET` | `/status` | **1** |
| Pegar QRCode - bytes | `GET` | `/qr-code` | **1** |
| Pegar QRCode - imagem | `GET` | `/qr-code/image` | **1** |
| Pegar QRCode - Telefone | `GET` | `/phone-code/{PHONE_NUMBER}` | 2 |
| Desconectar instância | `GET` | `/disconnect` | **1** |
| Reiniciar instância | `GET` | `/restart` | 2 |
| Dados da instância | `GET` | `/me` | **1** |
| Renomear instância | `PUT` | `/update-name` | — |
| Leitura automática | `PUT` | `/update-auto-read-message` | — |
| Dados do celular | `GET` | `/device` | — |
| Rejeitar chamadas / Mensagem de ligação | `PUT` | `/update-call-reject-*` | — |
| Perfil (nome, imagem, descrição) | `PUT` | `/profile-*` | — |

Doc: [Instance](https://developer.z-api.io/instance/introduction)

---

### Messages (envio)

| Operação Postman | Método | Path | Fase fork |
|------------------|--------|------|-----------|
| Enviar texto simples | `POST` | `/send-text` | **1** |
| Enviar imagem | `POST` | `/send-image` | 2 |
| Enviar áudio | `POST` | `/send-audio` | 2 |
| Enviar vídeo | `POST` | `/send-video` | 2 |
| Enviar documentos | `POST` | `/send-document/{ext}` | 2 |
| Enviar sticker / GIF / PTV | `POST` | `/send-sticker`, `/send-gif`, `/send-ptv` | 3 |
| Enviar localização / contato | `POST` | `/send-location`, `/send-contact` | 3 |
| Responder mensagem | `POST` | `/send-text` (+ `messageId`) | 2 |
| Ler mensagens | `POST` | `/read-message` | 2 |
| Deletar mensagens | `DELETE` | `/messages` | 3 |
| Botões, listas, enquete, PIX | `POST` | `/send-button-*`, `/send-option-list`, … | 3 |
| Reação | `POST` | `/send-reaction`, `/send-remove-reaction` | 3 |

Body texto MVP: `{ "phone": "5544...", "message": "..." }`

Resposta envio: contém `messageId` (usar como `source_id`).

Doc: [Messages](https://developer.z-api.io/message/introduction)

---

### Webhooks (configuração)

Cada webhook é uma URL **dedicada** configurada com `PUT` + body `{ "value": "https://..." }`.

| Operação | Método | Path | Evento | Fase fork |
|----------|--------|------|--------|-----------|
| **Atualizar todos** | `PUT` | `/update-every-webhooks` | Todos de uma vez | **1** (preferido) |
| Ao receber | `PUT` | `/update-webhook-received` | Inbound | **1** (fallback) |
| Ao receber - Enviadas por mim também | `PUT` | `/update-webhook-received-delivery` | Echo outbound | — (filtrar) |
| Ao enviar | `PUT` | `/update-webhook-delivery` | Aceito pelo WhatsApp | **1** |
| Atualização no status de mensagens | `PUT` | `/update-webhook-message-status` | SENT/READ/… | **1** |
| Ao desconectar | `PUT` | `/update-webhook-disconnected` | Sessão perdida | **1** |
| Ao conectar | `PUT` | `/update-webhook-connected` | Sessão ativa | 2 |
| Atualização no status do chat | `PUT` | `/update-webhook-chat-presence` | Typing/presence | — |

Doc: [Webhooks](https://developer.z-api.io/webhooks/introduction)

**Nota Chatwoot:** preferir **uma rota multiplexada** no fork (`/webhooks/zapi/:instance_id`) que demux por campo `type` no JSON — ver [webhook-events.md](./webhook-events.md).

---

### Contacts

| Operação Postman | Método | Path | Fase fork |
|------------------|--------|------|-----------|
| Pegar contatos | `GET` | `/contacts?page=&pageSize=` | 2 |
| Pegar metadata do contato | `GET` | `/contacts/{phone}` | 2 |
| Número com WhatsApp? | `GET` | `/phone-exists/{phone}` | 2 |
| Validar números em lote | `POST` | `/phone-exists-batch` | 3 |
| Bloquear / Denunciar | `POST` | `/contacts/block`, `/contacts/report` | — |

---

### Chats

| Operação | Método | Path | Fase fork |
|----------|--------|------|-----------|
| Pegar chats | `GET` | `/chats` | 3 |
| Pegar metadata do Chat | `GET` | `/chats/{phone}` | 3 |
| Ler chat | `POST` | `/read-chat` | 2 |
| Arquivar / Fixar / Mutar | `POST` | `/archive-chat`, `/pin-chat`, `/mute-chat` | — |

---

### Message queue

| Operação | Método | Path | Fase fork |
|----------|--------|------|-----------|
| Ver fila | `GET` | `/queue` | — |
| Apagar fila / mensagem | `DELETE` | `/queue`, `/queue/{id}` | — |

Z-API usa fila interna assíncrona — o `messageId` retorna no POST de envio; delivery vem via webhook.

---

### Partners (provisionamento SaaS)

| Operação Postman | Método | Path | Auth | Fase fork |
|------------------|--------|------|------|-----------|
| Criando uma instância | `POST` | `/instances/integrator/on-demand` | Bearer `PARTNER_AUTH_TOKEN` | 2 |
| Assinando uma instância | `POST` | `/instances/integrator/on-demand/subscription` | Bearer | — |
| Cancelando uma instância | `DELETE` | `/instances/integrator/on-demand/cancel` | Bearer | — |
| Listando instâncias | `GET` | `/instances/integrator/on-demand` | Bearer | — |

Body create (exemplo Postman): webhooks inline + `name`, `sessionName`, `isDevice`, `businessDevice`.

MVP alternativo: operador cola `instance_id` + `instance_token` + `client_token` do painel Z-API.

---

### Pastas fora do escopo Chatwoot inicial

| Pasta Postman | Motivo |
|---------------|--------|
| Mobile | Onboarding sem QR — complexidade alta |
| Privacy | Configuração de conta WhatsApp |
| Groups / Communities / Newsletter | Chatwoot não modela |
| Calls | Projeto voz separado |
| Status | Stories WhatsApp |
| WhatsApp Business | Catálogo/etiquetas — fase futura |

---

## Documentação irmã (fork)

| Documento | Uso |
|-----------|-----|
| [../evolution-api/documentation-links.md](../evolution-api/documentation-links.md) | Provider já implementado |
| [../evolution-go/documentation-links.md](../evolution-go/documentation-links.md) | Provider planejado |
| [postman-validation.md](./postman-validation.md) | Inventário completo da collection |
| [webhook-events.md](./webhook-events.md) | Payloads inbound |
