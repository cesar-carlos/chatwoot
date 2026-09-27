# Popup visual — Plano de implementação (as-built)

Documento **as-built** da entrega de 27/set/2026. Decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Dar ao agente uma coluna **Popup** na tabela de preferências e mostrar o aviso nativo do navegador com o contato e o texto da mensagem, exceto quando essa conversa já está aberta na janela.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Helper `usePopupNotifications` | ✅ |
| 2 | Gancho em `onNotificationCreated` | ✅ |
| 3 | Coluna desktop e seção mobile | ✅ |
| 4 | i18n en + pt_BR | ✅ |
| 5 | Docs em `doc/feature/popup-notifications/` | ✅ |

---

## Detalhe técnico

### 1. Persistência

```js
// users.ui_settings
popup_notification_flags_by_account: {
  "1": ["popup_assigned_conversation_new_message"]
}
```

- A chave da conta é o `account_id` em string
- `withPopupFlagsForAccount` grava só a conta ativa e apaga a lista antiga `popup_notification_flags`
- Leitura: mapa da conta; se o mapa não existe, cai na lista antiga

### 2. Quando o aviso abre

`showPopupNotification` sai cedo se:

- o tipo não está na lista da **conta da notificação**, ou é `voice_call_incoming`
- `Notification` não existe ou a permissão não é `granted`
- a janela está visível e a URL já é `/conversations/<display_id>` dessa conversa

O corpo passa por `popupMessageBody`: se começa com `"Nome: "`, esse prefixo sai.

Título, corpo e ícone vêm do payload do cabo:

- `notification.primary_actor.meta.sender.name` / `.thumbnail`
- `notification.push_message_body`
- `primary_actor.id` é o `display_id` da conversa

### 3. Clique

`window.focus()`, `notification.close()`, depois `router.push` para `frontendURL(conversationUrl({ accountId, id: displayId }))`. O router é importado só no clique, para não puxar o grafo de rotas na carga do Action Cable.

### 4. Permissão na UI

Ao marcar um checkbox, se a permissão ainda é `default`, pede `Notification.requestPermission()`. Se o resultado não for `granted`, o flag não entra no array e o alerta `POPUP_PERMISSION_ERROR` aparece. Desmarcar não mexe na permissão nem na subscription de push.

---

## Arquivos

| Arquivo | Papel |
|---------|--------|
| `custom/app/javascript/dashboard/composables/usePopupNotifications.js` | Filtro, `new Notification`, navegação |
| `app/javascript/dashboard/helper/actionCable.js` | `// FORK:` chama o helper depois do gate de inbox |
| `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue` | Coluna, seção mobile, gravação em `ui_settings` |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | `POPUP`, seção mobile, erro de permissão |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Mesmas chaves |

Não há alteração em `NotificationBuilder`, `notification_settings` ou `public/sw.js`.

---

## Como testar

1. Perfil → Preferências de notificação → marcar Popup em “Uma nova mensagem foi criada e atribuída”.
2. Aceitar a permissão do navegador.
3. No desktop, deixar a aba do painel em segundo plano.
4. Receber uma mensagem numa conversa atribuída a esse agente.
5. O aviso do sistema mostra o nome do contato e o texto. O clique abre a conversa.

Não esperar o popup com a janela do painel em foco, nem com o PWA do celular suspenso.
