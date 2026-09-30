# PWA — Estado atual

Inventário do que existe no codebase (29/set/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Instalação na tela inicial | `<link rel="manifest" href="/manifest.json">` no layout do painel |
| Modo app | `display: standalone`, `start_url: "/"` |
| Cor da barra | `theme-color` e `background_color` `#2781F6` |
| Ícones Android | PNG de 36, 48, 72, 96, 144 e 192 px em `public/` |
| Ícones Apple | `apple-touch-icon` de 57 a 180 px no mesmo layout |
| Tile Windows | `msapplication-TileColor` / `msapplication-TileImage` |
| Interruptor | Some manifesto, ícones e `theme-color` se `DISPLAY_MANIFEST` for `false` |
| Worker | `public/sw.js` escuta `push` e `notificationclick` |
| Payload do push | JSON `{ title, tag, url }`. O worker mostra título e tag; a URL fica em `data.url` |
| Clique | Foca uma janela cuja URL é **igual** a `notification.data.url`, senão `clients.openWindow` |
| Registro | `verifyServiceWorkerExistence` em `pushHelper.js` |
| Reinscrição | Se já houver subscription, `App.vue` chama `registerSubscription` de novo |
| Permissão | Perfil → Notificações. Ligar push chama `Notification.requestPermission` e `pushManager.subscribe` |
| Chave | `window.chatwootConfig.vapidPublicKey`, vinda de `VAPID_PUBLIC_KEY` no layout |
| Servidor | `Notification::PushNotificationService` manda `WebPush.payload_send` para subscriptions `browser_push` |
| Preferência | Só envia se `push_<notification_type>` estiver ligado na conta |
| Subscription inválida | `ExpiredSubscription`, `InvalidSubscription` e `Unauthorized` destroem o registro |
| Aviso iOS | `isIosSafariWithoutPwa()` mostra `WAVOIP_IOS_PWA_HINT` (en + pt_BR) |

Detecção iOS do fork:

- user agent contém `iPad`, `iPhone` ou `iPod`
- não está em `matchMedia('(display-mode: standalone)')` nem em `navigator.standalone`
- o aviso fala de **chamada recebida**, não de todo tipo de notificação

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Offline / precache | `sw.js` não escuta `fetch` |
| Ícone 512×512 no manifesto | O arquivo para em 192 px. O Chrome usa 192 e 512 no critério de instalável |
| `apple-mobile-web-app-capable` | O layout não declara o meta. O iOS antigo depende dele para abrir sem a barra do Safari |
| Nome da instalação | Manifesto fixo em “Chatwoot”. Não lê `INSTALLATION_NAME` |
| `start_url` do painel | Abre `/`, não `/app` |
| Worker antes do login | O registro está em `initializeAccount`. A tela de login já tem o manifesto, sem worker |
| Prompt de instalação | Não há `beforeinstallprompt` nem botão |
| Workbox no build | `workbox-config.js` não está em script do `package.json`. O destino dele é o mesmo `public/sw.js` |
| Foco no clique | A comparação é `client.url === notification.data.url`. Query string ou barra final diferente abre janela nova |
| Popup com o PWA suspenso | O sistema congela o JavaScript. Ver [popup-notifications](../popup-notifications/current-state.md) |
| FCM / app nativo | O mesmo service também manda FCM. Isso não passa por `sw.js` |

---

## Relação com os outros avisos

| Canal | Onde configura | Quando chega | Peça deste PWA |
|-------|----------------|--------------|----------------|
| Som | Alertas de áudio | Página viva, `message.created` | Nenhuma |
| Popup | Coluna Popup | Página viva, exceto a conversa já aberta | Nenhuma |
| Push do painel | Coluna Notificação | Aba fechada ou PWA suspenso | `sw.js` + VAPID |
| Chamada Wavoip na página | Widget de chamada | Página viva | Só o aviso de que o iOS exige o app instalado |
| E-mail | Coluna E-mail | Job no servidor | Nenhuma |
