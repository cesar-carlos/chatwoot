# Popup visual — Estado atual

Inventário do que existe no codebase após a revisão de 01/out/2026.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Coluna desktop | Grid 6 / 2 / 2 / 2: tipo, e-mail, notificação do sistema, “Pop-up notification”; títulos quebram linha sem sobreposição e linhas crescem com o texto |
| Lista mobile | Terceira seção “Pop-up notification”, sem a linha de chamada de voz; rótulos clicáveis |
| Persistência | `ui_settings.popup_notification_flags_by_account[accountId]`, via action estrita com rollback; controles ficam bloqueados durante o salvamento para impedir gravações concorrentes |
| Lista antiga | `popup_notification_flags` (flat) só é lida se o mapa por conta ainda não existe |
| Corpo | Texto da mensagem; o prefixo `"Nome: "` sai quando o título já é o contato |
| Janela em foco | Aviso abre se conta ou conversa da URL forem diferentes |
| Conversa lida | `conversation.read` fecha todos os avisos daquela `account_id + display_id`, inclusive o aviso móvel se a criação ainda não terminou |
| Chamada de voz | Célula com “—”; CTA explícito concede a permissão usada pelo Wavoip |
| Permissão | Primeiro checkbox ou CTA pede `Notification.requestPermission()` |
| Permissão negada | Checkbox não grava; `useAlert` com `POPUP_PERMISSION_ERROR` |
| Disparo | `onNotificationCreated` chama `showPopupNotification` depois de `addNotification` |
| Gate | Mesmo `canAccessInboxView` do sino, calculado para a conta do evento |
| Nova conversa | O overlay do `NotificationBuilder` cria `conversation_creation` quando apenas o Pop-up dessa conta está marcado |
| Título | `primary_actor.meta.sender.name`, senão o `notification_type` |
| Ícone | Thumbnail do contato ou `/brand-assets/logo_thumbnail.svg` |
| Agrupamento | `tag` `<notification_type>_<display_id>_<notification_id>` corresponde ao Push do mesmo evento |
| Mobile com painel vivo | Se `new Notification` falhar, `showNotification` do service worker tenta mostrar o aviso; falhas geram alerta traduzido uma vez por sessão |
| Clique | Desktop foca a janela; service worker prefere janela da mesma conta, reutiliza cliente adequado ou abre nova janela |
| Tipos | Os mesmos da tabela, exceto `voice_call_incoming` |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Popup da conversa que já está aberta | Conta e `display_id` da URL são os mesmos; o agente está vendo a mensagem |
| Popup com PWA/aba suspensa no celular | O OS congela o JavaScript e o websocket cai |
| Aviso com o app fechado | Continua sendo Web Push (inscrição neste dispositivo + coluna Push + VAPID) |
| Checkbox de chamada de voz | `notifyIncomingWavoipOffer` usa a permissão concedida pelo CTA genérico |
| Nova coluna no banco | Preferência é dado de UI, não canal de entrega do servidor |
| Toast dentro da página | Só o aviso nativo do sistema operacional; em primeiro plano, o SO decide como apresentá-lo |
| Garantia de exibição pelo aparelho | A API confirma a tentativa; o sistema operacional controla a apresentação. É necessário validar em aparelhos reais |

---

## Relação com os outros avisos

| Canal | Onde configura | Quando chega |
|-------|----------------|--------------|
| Som | Alertas de áudio (`enable_audio_alerts`) | `message.created`, página viva |
| Push | Coluna Notificação | Service worker, aba pode estar fechada |
| E-mail | Coluna E-mail | Job no servidor |
| Popup | Coluna “Pop-up notification” | Página viva e conectada, exceto na conversa que já está aberta |
