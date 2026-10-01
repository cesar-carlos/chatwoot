# Popup visual — Plano de implementação (as-built)

Documento **as-built**, revisado em 01/out/2026. Decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Dar ao agente uma coluna **Pop-up notification** na tabela de preferências e mostrar o aviso nativo do navegador com o contato e o texto da mensagem, exceto quando essa conversa já está aberta na janela.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Helper `usePopupNotifications` | ✅ |
| 2 | Gancho em `onNotificationCreated` | ✅ |
| 3 | Coluna desktop responsiva e seção mobile com rótulos clicáveis | ✅ |
| 4 | Textos explicativos em en + pt_BR; rótulo fixo “Pop-up notification” | ✅ |
| 5 | Docs em `doc/feature/popup-notifications/` | ✅ |
| 6 | Fallback via service worker quando o construtor `Notification` falha no mobile | ✅ |
| 7 | Criação de `conversation_creation` com preferência somente Pop-up | ✅ |
| 8 | Fechamento de múltiplos avisos, bloqueio de salvamentos concorrentes e feedback de falha | ✅ |

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
- A gravação usa uma action Vuex que propaga falhas; em erro, a seleção anterior é restaurada e a interface informa a falha
- Os checkboxes de cada grupo ficam bloqueados enquanto a respectiva gravação está pendente

### 2. Quando o aviso abre

`showPopupNotification` sai cedo se:

- o tipo não está na lista da **conta da notificação**, ou é `voice_call_incoming`
- `Notification` não existe ou a permissão não é `granted`
- a janela está visível e a URL já é `/accounts/<account_id>/conversations/<display_id>` dessa conversa

O corpo passa por `popupMessageBody`: se começa com `"Nome: "`, esse prefixo sai.

Título, corpo e ícone vêm do payload do cabo:

- `notification.primary_actor.meta.sender.name` / `.thumbnail`
- `notification.push_message_body`
- `primary_actor.id` é o `display_id` da conversa

### 3. Exibição e clique

No desktop, `new Notification` cria o aviso. Se esse construtor falhar, como ocorre na maioria dos navegadores móveis, a página registra ou reutiliza `/sw.js` e chama `registration.showNotification`. Isso não cria uma inscrição Web Push.

No desktop, o clique faz `window.focus()`, fecha o aviso e chama `router.push` para a conversa. O router é importado só no clique. No aviso do service worker, o handler `notificationclick` fecha o aviso, prefere uma janela do painel da mesma conta e navega até a conversa; se houver apenas uma janela do painel, pode reutilizá-la mesmo em outra conta, ou abre nova janela quando não houver cliente adequado. A tag corresponde à do Web Push do mesmo evento: `<notification_type>_<display_id>_<notification_id>`.

O cliente acompanha todos os avisos da mesma conversa. Ao receber `conversation.read`, fecha cada um; se um aviso do service worker ainda estiver sendo criado, fecha assim que a criação terminar. Falha na criação chega ao Action Cable e mostra um único alerta traduzido por sessão, sem repetir um toast para cada mensagem.

### 4. Permissão na UI

Ao marcar um checkbox, se a permissão ainda é `default`, pede `Notification.requestPermission()`. Se o resultado não for `granted`, o flag não entra no array e o alerta `POPUP_PERMISSION_ERROR` aparece. Uma ação explícita separada também concede a permissão usada pelos alertas de chamada de voz. Desmarcar não mexe na permissão nem na subscription de push.

A permissão comum de notificações não ativa Web Push. A inscrição Push tem opt-in próprio por dispositivo: só é criada pelo seletor Push e não é recriada depois de o usuário desativá-la.

---

## Arquivos

| Arquivo | Papel |
|---------|--------|
| `custom/app/javascript/dashboard/composables/usePopupNotifications.js` | Filtro, `new Notification`, fallback `showNotification`, navegação |
| `custom/app/builders/custom/notification_builder.rb` | Permite criar evento `conversation_creation` para a preferência Pop-up da conta |
| `app/javascript/dashboard/helper/actionCable.js` | `// FORK:` chama o helper depois do gate de inbox |
| `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue` | Coluna, seção mobile, gravação em `ui_settings` |
| `app/javascript/dashboard/store/modules/auth.js` | Action estrita para persistir preferências com rollback na UI |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | Textos explicativos e erros |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Mesmas chaves |
| `public/sw.js` | Clique com preferência por cliente da mesma conta |

O Pop-up depende de `notification.created` via Action Cable e não da inscrição Web Push. Para `conversation_creation`, o builder consulta a preferência Pop-up além das flags de e-mail/Push ao decidir criar o evento. No mobile, o service worker apenas exibe e trata o clique do aviso iniciado pela página; com a PWA suspensa ou fechada, o recebimento depende do Web Push separado.

---

## Como testar

1. Perfil → Preferências de notificação → marcar Pop-up notification em “Uma nova mensagem foi criada e atribuída”.
2. Aceitar a permissão do navegador.
3. No desktop, deixar a aba do painel em segundo plano.
4. Receber uma mensagem numa conversa atribuída a esse agente.
5. O aviso do sistema mostra o nome do contato e o texto. O clique abre a conversa da conta correta.
6. Simular erro ao salvar as preferências e confirmar que a seleção anterior é restaurada.
7. Na PWA móvel instalada, manter o painel aberto em outra conversa e confirmar que o aviso é exibido via service worker e abre a conversa correta.
8. Marcar somente Pop-up para nova conversa, deixar e-mail e Push desmarcados e confirmar a criação do aviso.
9. Gerar dois avisos para a mesma conversa e marcar como lida; ambos devem fechar. Repetir enquanto a criação do aviso móvel ainda está pendente.
10. Simular falha do service worker e confirmar um alerta de falha, sem repetição por mensagem; testar múltiplas janelas em contas distintas e verificar a preferência pela conta de destino.

Com o painel visível, esperar o Pop-up quando outra conversa estiver aberta, mas não quando a mesma conversa da mesma conta já estiver em exibição. Não esperar Pop-up com a PWA suspensa; esse cenário é atendido exclusivamente por Web Push. A apresentação do aviso em primeiro plano depende do sistema operacional.
