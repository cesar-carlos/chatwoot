# Attachment Download State — Plano de implementação (as-built)

Documento **as-built** do MVP entregue em 16/jul/2026. Fonte normativa para manutenção; decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Permitir que o agente veja quais anexos de **arquivo** já baixou (e quantas vezes), com estado **persistido só no browser**, sincronizado entre chip, bubble e sidebar na mesma aba — sem backend.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Composable `useAttachmentDownloadState` + key localStorage | ✅ |
| 2 | Chip `File.vue` — downloadFile + UI estado | ✅ |
| 3 | Bubble `File.vue` + `action.disabled` em BaseAttachment | ✅ |
| 4 | Sidebar `SharedAttachments/Files.vue` | ✅ |
| 5 | i18n EN | ✅ |
| 6 | Docs em `doc/feature/attachment-download-state/` | ✅ |

---

## Detalhe técnico

### 1. Persistência

```js
// key
`attachmentDownloadState::{accountId}::{userId}`

// value per attachmentId (stringified)
{ count: number, lastDownloadedAt: number }
```

- Helper: `LocalStorage.get` / `LocalStorage.set`
- Constante: `LOCAL_STORAGE_KEYS.ATTACHMENT_DOWNLOAD_STATE`
- Scope via Vuex getters `getCurrentAccountId` / `getCurrentUserID`
- Um único `store.watch` (não amarrado ao lifecycle dos chips) recarrega o scope

### 2. API do composable

```js
const { isDownloaded, downloadCount, markDownloaded } =
  useAttachmentDownloadState();

isDownloaded(attachmentId);  // boolean
downloadCount(attachmentId); // number
markDownloaded(attachmentId); // increment + persist
```

Estado reativo compartilhado: module-level `ref(downloadRecords)`.

### 3. Fluxo de download

1. Click → `downloadFile({ url, type, extension })`
2. Sucesso → `markDownloaded(id)`
3. Falha → `useAlert(DOWNLOAD_ERROR)` (não marca)

Chip e bubble **deixam de usar** `<a href>` para permitir marcar com confiança.

### 4. Fork conventions

| Preferir | Uso |
|----------|-----|
| `custom/` | Composable de estado |
| `customDashboard/helper/downloadFile` | Já existia (same-origin) |
| `// FORK:` fino | Imports + key localStorage + BaseAttachment disabled |
| Sem | Migration, controller, store Vuex novo |

---

## Mapa de arquivos

| Path | Tipo |
|------|------|
| `custom/app/javascript/dashboard/composables/useAttachmentDownloadState.js` | novo |
| `app/javascript/dashboard/constants/localStorage.js` | FORK key |
| `app/javascript/dashboard/components-next/message/chips/File.vue` | FORK download + UI |
| `app/javascript/dashboard/components-next/message/bubbles/File.vue` | FORK download + UI |
| `app/javascript/dashboard/components-next/message/bubbles/BaseAttachment.vue` | FORK `action.disabled` |
| `app/javascript/dashboard/components-next/SharedAttachments/Files.vue` | FORK mark + UI |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | strings EN |

---

## Teste manual

1. Abrir conversa com vários PDFs.
2. Baixar o primeiro pelo chip → ícone vira check; hover mostra `Downloaded`.
3. Abrir sidebar Attachments → mesmo arquivo com check teal.
4. Baixar de novo → `Downloaded · 2×`.
5. F5 → estado permanece.
6. (Opcional) Outro usuário no mesmo browser → contagem separada.

---

## Relação com outras features

| Feature | Relação |
|---------|---------|
| [message-attachment-retention](../message-attachment-retention/implementation.md) | Independente — retenção apaga blobs no server; estado local fica órfão até o id sumir da UI |
| Download same-origin FORK | Pré-requisito reutilizado |
