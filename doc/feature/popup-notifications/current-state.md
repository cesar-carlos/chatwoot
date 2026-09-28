# Popup visual — Estado atual

Inventário do que existe no codebase após a revisão de 28/set/2026.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Coluna desktop | Grid 6 / 2 / 2 / 2: tipo, e-mail, notificação do sistema, alerta com painel aberto |
| Lista mobile | Terceira seção “Alertas com painel aberto”, sem a linha de chamada de voz |
| Persistência | `ui_settings.popup_notification_flags_by_account[accountId]`, via action estrita com rollback |
| Lista antiga | `popup_notification_flags` (flat) só é lida se o mapa por conta ainda não existe |
| Corpo | Texto da mensagem; o prefixo `"Nome: "` sai quando o título já é o contato |
| Janela em foco | Aviso abre se conta ou conversa da URL forem diferentes |
| Conversa lida | `conversation.read` fecha por `account_id + display_id` |
| Chamada de voz | Célula com “—”; CTA explícito concede a permissão usada pelo Wavoip |
| Permissão | Primeiro checkbox ou CTA pede `Notification.requestPermission()` |
| Permissão negada | Checkbox não grava; `useAlert` com `POPUP_PERMISSION_ERROR` |
| Disparo | `onNotificationCreated` chama `showPopupNotification` depois de `addNotification` |
| Gate | Mesmo `canAccessInboxView` do sino |
| Título | `primary_actor.meta.sender.name`, senão o `notification_type` |
| Ícone | Thumbnail do contato ou `/brand-assets/logo_thumbnail.svg` |
| Agrupamento | `tag` `chatwoot-popup-<account_id>-<display_id>` substitui o aviso anterior da conversa |
| Clique | Foca a janela, fecha o aviso e abre `/app/accounts/:id/conversations/:displayId` |
| Tipos | Os mesmos da tabela, exceto `voice_call_incoming` |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Popup da conversa que já está aberta | Conta e `display_id` da URL são os mesmos; o agente está vendo a mensagem |
| Popup com PWA/aba suspensa no celular | O OS congela o JavaScript e o websocket cai |
| Aviso com o app fechado | Continua sendo Web Push (coluna Notificação + VAPID) |
| Checkbox de chamada de voz | `notifyIncomingWavoipOffer` usa a permissão concedida pelo CTA genérico |
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
