# Popup visual — Estado atual

Inventário das correções de `fix/notification-delivery-hardening`, integradas à `main`, publicadas no fork e implantadas no release `f58ca95d4d` em 01/out/2026. Web e worker estão na mesma versão; o smoke público passou. A homologação da apresentação dos avisos em aparelhos continua pendente.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Coluna desktop | Grid 6 / 2 / 2 / 2: tipo, e-mail, notificação do sistema, “Pop-up notification”; títulos quebram linha sem sobreposição e linhas crescem com o texto |
| Lista mobile | Terceira seção “Pop-up notification”, sem a linha de chamada de voz; rótulos clicáveis |
| Persistência | `ui_settings.popup_notification_flags_by_account[accountId]`, via action estrita com rollback; controles ficam bloqueados durante o salvamento para impedir gravações concorrentes |
| Lista antiga | `popup_notification_flags` (flat) só é lida se o mapa por conta ainda não existe |
| Corpo | Texto da mensagem; o prefixo `"Nome: "` sai quando o título já é o contato |
| Janela em foco | Compara parâmetros normalizados do router; cobre todas as rotas de conversa e não confunde o ID de uma visão personalizada com uma conversa |
| Leitura individual | `notification.updated` com `read_at` fecha somente `account_id + notification_id`, inclusive criação pendente |
| Leitura em lote | `notifications.read` é enviado somente ao destinatário, com `user_id`, conta, conversa opcional e `through_notification_id`; banco, store e fechamento respeitam o mesmo limite |
| Leitura pelo contato | `conversation.read` não fecha a notificação do agente |
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
| Falha no clique | Cliente desaparecido, navegação rejeitada ou foco rejeitado levam à abertura de nova janela na mesma origem |
| Preferências | Bloqueadas até o carregamento bem-sucedido, com erro/retry, proteção de troca de conta e rollback |
| Diagnóstico do dispositivo | CTA só aparece com endpoint confirmado; limite de três testes por minuto por usuário |
| Ações | Quando a plataforma oferece ações, Pop-up usa aviso persistente também no desktop. Backend idempotente e autorizado; o worker não faz chamadas autenticadas nem guarda credenciais |
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
| Resposta e silenciamento | Fora do escopo; as únicas ações são abrir e marcar como lida |
| Intenção expirada | O nonce do clique é consumido uma vez, dura até 60 segundos e não sobrevive ao reinício do worker. Se expirar, a UI orienta a operação manual, sem escrever automaticamente |

Validação e critérios ainda pendentes em [validation-report.md](./validation-report.md).

---

## Relação com os outros avisos

| Canal | Onde configura | Quando chega |
|-------|----------------|--------------|
| Som | Alertas de áudio (`enable_audio_alerts`) | `message.created`, página viva |
| Push | Coluna Notificação | Service worker, aba pode estar fechada |
| E-mail | Coluna E-mail | Job no servidor |
| Popup | Coluna “Pop-up notification” | Página viva e conectada, exceto na conversa que já está aberta |
