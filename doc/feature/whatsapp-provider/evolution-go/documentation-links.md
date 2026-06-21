# Links de documentação — Evolution Go

Índice oficial alinhado à [collection Postman Evolution GO](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) e ao OpenAPI em `docs.evolutionfoundation.com.br/evolution-go/*`.

**Base URL docs:** https://docs.evolutionfoundation.com.br/evolution-go/

**Última revisão:** jun/2026 — paths confirmados via OpenAPI oficial; Group/Chat/advanced-settings marcados ⚠️ até spike

**Manutenção:** `./sync-documentation-links.sh` — diff `llms.txt` vs este arquivo

## Hub e runtime

| Recurso | URL |
|---------|-----|
| Hub | https://docs.evolutionfoundation.com.br/en/evolution-go |
| Getting started | https://docs.evolutionfoundation.com.br/en/evolution-go/getting-started |
| Instalação | https://docs.evolutionfoundation.com.br/en/evolution-go/installation |
| Índice máquina | https://docs.evolutionfoundation.com.br/llms.txt |
| GitHub | https://github.com/evolution-foundation/evolution-go |
| Docker Hub | https://hub.docker.com/r/evoapicloud/evolution-go |
| Postman | https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go |
| Swagger (runtime) | `{base_url}/swagger/index.html` |

---

## Postman → documentação oficial (por pasta)

### Instance

| Operação | Método | Path | Doc oficial |
|----------|--------|------|-------------|
| Create | `POST` | `/instance/create` | [create-a-new-instance](https://docs.evolutionfoundation.com.br/evolution-go/create-a-new-instance) |
| Connect | `POST` | `/instance/connect` | [connect-to-instance](https://docs.evolutionfoundation.com.br/evolution-go/connect-to-instance) |
| Get all | `GET` | `/instance/all` | [get-all-instances](https://docs.evolutionfoundation.com.br/evolution-go/get-all-instances) |
| QR code | `GET` | `/instance/qr` | [get-instance-qr-code](https://docs.evolutionfoundation.com.br/evolution-go/get-instance-qr-code) |
| Status | `GET` | `/instance/status` | [get-instance-status](https://docs.evolutionfoundation.com.br/evolution-go/get-instance-status) |
| Pairing code | `POST` | `/instance/pair` | [request-pairing-code](https://docs.evolutionfoundation.com.br/evolution-go/request-pairing-code) |
| Disconnect | `POST` | `/instance/disconnect` | [disconnect-from-instance](https://docs.evolutionfoundation.com.br/evolution-go/disconnect-from-instance) |
| Logout | `DELETE` | `/instance/logout` | [logout-from-instance](https://docs.evolutionfoundation.com.br/evolution-go/logout-from-instance) |
| Delete | `DELETE` | `/instance/delete/{instanceId}` | [delete-instance](https://docs.evolutionfoundation.com.br/evolution-go/delete-instance) |
| Delete proxy | `DELETE` | `/instance/proxy/{instanceId}` | [delete-proxy](https://docs.evolutionfoundation.com.br/evolution-go/delete-proxy) |
| Advanced settings | `POST` | `/instance/{instanceId}/advanced-settings` ⚠️ | Confirmar Swagger — Fase 2 fork |

**Auth Instance:** `apikey` header — global key (create/all/delete) ou instance token (connect/qr/status/pair/disconnect/logout/advanced-settings).

---

### Send Message

| Operação | Método | Path | Doc oficial | Fase fork |
|----------|--------|------|-------------|-----------|
| Text | `POST` | `/send/text` | [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message) | **1** |
| Media | `POST` | `/send/media` | [send-a-media-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-media-message) | 2 |
| Location | `POST` | `/send/location` | [send-a-location-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-location-message) | 3 |
| Contact | `POST` | `/send/contact` | [send-a-contact-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-contact-message) | 3 |
| Link | `POST` | `/send/link` | [send-a-link-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-link-message) | 3 |
| Sticker | `POST` | `/send/sticker` | [send-a-sticker-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-sticker-message) | 3 |
| Poll | `POST` | `/send/poll` | [send-a-poll-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-poll-message) | 3 |

**Auth Send:** `apikey: {instance_token}` (OpenAPI marca `security: []` mas 401 exige apikey).

**Resposta send:** `data.Info.ID` — struct whatsmeow PascalCase (não `key.id` Baileys).

---

### Message

| Operação | Método | Path | Doc oficial | Fase fork |
|----------|--------|------|-------------|-----------|
| Mark read | `POST` | `/message/markread` | [mark-a-message-as-read](https://docs.evolutionfoundation.com.br/evolution-go/mark-a-message-as-read) | 2 |
| Status | `POST` | `/message/status` | [get-message-status](https://docs.evolutionfoundation.com.br/evolution-go/get-message-status) | 2 |
| React | `POST` | `/message/react` | [react-a-message](https://docs.evolutionfoundation.com.br/evolution-go/react-a-message) | 3 |
| Presence (typing) | `POST` | `/message/presence` | [set-chat-presence](https://docs.evolutionfoundation.com.br/evolution-go/set-chat-presence) | 3 |
| Edit | `POST` | `/message/edit` | [edit-a-message](https://docs.evolutionfoundation.com.br/evolution-go/edit-a-message) | 3 |
| Delete for everyone | `POST` | `/message/delete` | [delete-a-message-for-everyone](https://docs.evolutionfoundation.com.br/evolution-go/delete-a-message-for-everyone) | 3 |
| Download image | `POST` | `/message/downloadimage` | [download-an-image](https://docs.evolutionfoundation.com.br/evolution-go/download-an-image) | 2 |

---

### Chat

| Operação | Doc oficial | Fase fork |
|----------|-------------|-----------|
| Archive | [archive-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/archive-a-chat) | — |
| Mute | [mute-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/mute-a-chat) | — |
| Pin | [pin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/pin-a-chat) | — |
| Unpin | [unpin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/unpin-a-chat) | — |

---

### Group

> ⚠️ Paths abaixo têm links oficiais de documentação mas **paths REST não confirmados no spike** — validar na collection Postman (pasta Group) ou Swagger runtime antes de implementar Fase 3+.

| Operação | Método | Path (típico) | Doc oficial |
|----------|--------|---------------|-------------|
| Create | `POST` | `/group/create` | [create-group](https://docs.evolutionfoundation.com.br/evolution-go/create-group) |
| Info | `POST` | `/group/info` | [get-group-info](https://docs.evolutionfoundation.com.br/evolution-go/get-group-info) |
| Invite link | `POST` | `/group/invitelink` | [get-group-invite-link](https://docs.evolutionfoundation.com.br/evolution-go/get-group-invite-link) |
| Join link | `POST` | `/group/join` | [join-group-link](https://docs.evolutionfoundation.com.br/evolution-go/join-group-link) |
| List | `GET` | `/group/list` | [list-groups](https://docs.evolutionfoundation.com.br/evolution-go/list-groups) |
| My groups | `GET` | `/group/my` | [get-my-groups](https://docs.evolutionfoundation.com.br/evolution-go/get-my-groups) |
| Set name | `POST` | `/group/name` | [set-group-name](https://docs.evolutionfoundation.com.br/evolution-go/set-group-name) |
| Update participant | `POST` | `/group/participant` | [update-participant](https://docs.evolutionfoundation.com.br/evolution-go/update-participant) |
| Set photo | `POST` | `/group/photo` | [set-group-photo](https://docs.evolutionfoundation.com.br/evolution-go/set-group-photo) |

**Fork MVP:** ignorar grupos (`ignore_groups: true`).

---

### User

| Operação | Doc oficial |
|----------|-------------|
| Get user | [get-a-user](https://docs.evolutionfoundation.com.br/evolution-go/get-a-user) |
| Check user | [check-a-user](https://docs.evolutionfoundation.com.br/evolution-go/check-a-user) |
| Avatar | [get-a-users-avatar](https://docs.evolutionfoundation.com.br/evolution-go/get-a-users-avatar) |
| Contacts | [get-a-users-contacts](https://docs.evolutionfoundation.com.br/evolution-go/get-a-users-contacts) |
| Privacy settings | [get-a-users-privacy-settings](https://docs.evolutionfoundation.com.br/evolution-go/get-a-users-privacy-settings) |
| Profile picture | [set-a-users-profile-picture](https://docs.evolutionfoundation.com.br/evolution-go/set-a-users-profile-picture) |
| Block | [block-a-contact](https://docs.evolutionfoundation.com.br/evolution-go/block-a-contact) |
| Unblock | [unblock-a-contact](https://docs.evolutionfoundation.com.br/evolution-go/unblock-a-contact) |
| Block list | [get-a-users-block-list](https://docs.evolutionfoundation.com.br/evolution-go/get-a-users-block-list) |

---

### Label

| Operação | Doc oficial |
|----------|-------------|
| Add to chat | [add-label-to-chat](https://docs.evolutionfoundation.com.br/evolution-go/add-label-to-chat) |
| Remove from chat | [remove-label-from-chat](https://docs.evolutionfoundation.com.br/evolution-go/remove-label-from-chat) |
| Add to message | [add-label-to-message](https://docs.evolutionfoundation.com.br/evolution-go/add-label-to-message) |
| Remove from message | [remove-label-from-message](https://docs.evolutionfoundation.com.br/evolution-go/remove-label-from-message) |
| Edit label | [edit-label](https://docs.evolutionfoundation.com.br/evolution-go/edit-label) |

---

### Call · Community · Newsletter · Polls · Server

Pastas Postman presentes na collection — fora do escopo MVP mensagens 1:1. Consultar Postman + Swagger para paths exatos.

---

## Webhooks — eventos `subscribe`

Configurados em `POST /instance/connect` body `subscribe: []`.

| Evento | Uso Chatwoot | Fase |
|--------|--------------|------|
| `MESSAGE` | Inbound texto/mídia | 1 |
| `CONNECTION` | Status conexão | 1 |
| `QRCODE` | QR no wizard | 1 |
| `READ_RECEIPT` | Status read | 2 |
| `SEND_MESSAGE` | Echo outbound — filtrar | — |
| `GROUP` | Ignorar MVP | — |
| `CALL` | Voz — projeto separado | — |

Default connect retorna `eventString` com todos os eventos se `subscribe` omitido — **restringir no fork** para reduzir ruído.

---

## OpenAPI specs (repo docs)

| Arquivo | Escopo |
|---------|--------|
| `evo-go-instance.yaml` | Instance lifecycle |
| `send-message.yaml` | `/send/*` |
| `evo-go-message.yaml` | `/message/*` |
| `evo-go-group.yaml` | `/group/*` |

---

## Documentação irmã (fork)

| Documento | Uso |
|-----------|-----|
| [../evolution-api/documentation-links.md](../evolution-api/documentation-links.md) | Evolution API Node |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | Divergências |
| [postman-validation.md](./postman-validation.md) | Validação collection |
| [api-reference.md](./api-reference.md) | Referência implementação |
