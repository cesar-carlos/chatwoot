# Popup visual — Estado atual

Inventário do que existe no codebase após a entrega (27/set/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Coluna desktop | Grid 6 / 2 / 2 / 2: tipo, e-mail, notificação, popup |
| Lista mobile | Terceira seção “Notificações em popup”, sem a linha de chamada de voz |
| Persistência | `ui_settings.popup_notification_flags_by_account[accountId]` |
| Lista antiga | `popup_notification_flags` (flat) só é lida se o mapa por conta ainda não existe |
| Corpo | Texto da mensagem; o prefixo `"Nome: "` sai quando o título já é o contato |
| Janela em foco | Aviso abre se a URL não for `/conversations/<id>` daquela conversa |
| Conversa lida | `conversation.read` fecha o aviso daquele `display_id` |
| Chamada de voz | Célula com “—” e nota de que o popup de chamada já existe |
| Permissão | Primeiro checkbox pede `Notification.requestPermission()` |
| Permissão negada | Checkbox não grava; `useAlert` com `POPUP_PERMISSION_ERROR` |
| Disparo | `onNotificationCreated` chama `showPopupNotification` depois de `addNotification` |
| Gate | Mesmo `canAccessInboxView` do sino |
| Título | `primary_actor.meta.sender.name`, senão o `notification_type` |
| Ícone | Thumbnail do contato ou `/brand-assets/logo_thumbnail.svg` |
| Agrupamento | `tag` `chatwoot-popup-<display_id>` substitui o aviso anterior da conversa |
| Clique | Foca a janela, fecha o aviso e abre `/app/accounts/:id/conversations/:displayId` |
| Tipos | Os mesmos da tabela, exceto `voice_call_incoming` |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Popup da conversa que já está aberta | A URL já é essa conversa; o agente está vendo a mensagem |
| Popup com PWA/aba suspensa no celular | O OS congela o JavaScript e o websocket cai |
| Aviso com o app fechado | Continua sendo Web Push (coluna Notificação + VAPID) |
| Checkbox de chamada de voz | `notifyIncomingWavoipOffer` já mostra o popup de chamada |
| Nova coluna no banco | Preferência é dado de UI, não canal de entrega do servidor |
| Toast dentro da página | Só o aviso nativo do sistema operacional |

---

## Relação com os outros avisos

| Canal | Onde configura | Quando chega |
|-------|----------------|--------------|
| Som | Alertas de áudio (`enable_audio_alerts`) | `message.created`, página viva |
| Push | Coluna Notificação | Service worker, aba pode estar fechada |
| E-mail | Coluna E-mail | Job no servidor |
| Popup | Coluna Popup | Página viva, exceto na conversa que já está aberta |
