# Attachment Download State — Estado atual

Inventário do que existe no codebase após o MVP (16/jul/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Marcar download | Após `downloadFile` com sucesso → `markDownloaded(id)` |
| Contagem | Incrementa `count` a cada download bem-sucedido |
| Timestamp | `lastDownloadedAt` (epoch ms) no registro local |
| Escopo | Isolado por `accountId` + `userId` no mesmo browser |
| Sync na aba | `ref` module-level — chip, bubble e sidebar atualizam juntos |
| Chip arquivo | Check teal + badge N× + tooltip Download again; right-click mark/clear |
| Bubble arquivo | Label Downloaded · Download again; estilo teal; Mark as done / Clear |
| Sidebar files | Filtro All/Pending/Downloaded; progresso; check + badge; right-click |
| Media (image/audio/gallery/sidebar) | Mesmo estado visual pós-download |
| Lista de conversas | Check teal no preview quando last attachment baixado |
| Microanimação | `isJustMarked` ~200ms scale no ícone |
| Prune | Máx. 500 entradas (LRU por `lastDownloadedAt`) |
| Persistência reload | Mantém estado após F5 no mesmo browser/agente |
| Erro | `useAlert` com `DOWNLOAD_ERROR` (sem marcar como baixado) |
| Alias hosts | Download via helper FORK same-origin Active Storage |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Estado “impresso” | Browser não notifica impressão |
| Sync entre PCs / browsers | Só localStorage |
| Sync entre agentes no mesmo PC | Isolado por `userId` (proposital) |
| Limpeza global no logout / profile | Ainda no backlog |
| Backend / API / migration | Desnecessário no happy path |
| i18n pt/pt_BR | Regra do fork: só EN |
| Specs automatizados | Regra do core: só se pedido |

---

## Mapa de arquivos

| Path | Papel |
|------|--------|
| `custom/app/javascript/dashboard/composables/useAttachmentDownloadState.js` | Estado + persistência |
| `custom/app/javascript/dashboard/helper/downloadFile.js` | Download same-origin (já existia) |
| `app/javascript/dashboard/constants/localStorage.js` | Key `ATTACHMENT_DOWNLOAD_STATE` |
| `app/javascript/dashboard/components-next/message/chips/File.vue` | Chip + UI estado |
| `app/javascript/dashboard/components-next/message/bubbles/File.vue` | Bubble + UI estado |
| `app/javascript/dashboard/components-next/message/bubbles/BaseAttachment.vue` | `action.disabled` (loading) |
| `app/javascript/dashboard/components-next/SharedAttachments/Files.vue` | Sidebar + UI estado |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | Strings EN |

---

## Shape no localStorage

**Chave:**

```text
attachmentDownloadState::{accountId}::{userId}
```

**Valor (JSON):**

```json
{
  "12345": { "count": 2, "lastDownloadedAt": 1721160000000 },
  "67890": { "count": 1, "lastDownloadedAt": 1721160100000 }
}
```

---

## Critérios de pronto (validação manual)

1. Baixar PDF no chat → chip/bubble passam a “baixado” na hora.
2. Mesmo arquivo na sidebar Shared files reflete o check.
3. Segundo download → tooltip/label `Downloaded · 2×`.
4. Reload mantém estado no mesmo agente/browser.
5. Outro `userId` no mesmo browser não herda a contagem.
6. Falha de download → toast de erro; ícone permanece “não baixado”.
