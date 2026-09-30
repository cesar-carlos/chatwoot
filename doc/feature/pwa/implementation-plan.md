# PWA — Plano de implementação (as-built)

Documento **as-built** do shell que já está no repositório em 29/set/2026. Decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

Não houve uma entrega nova de PWA nesta data. O manifesto e o worker vêm do upstream. O fork adiciona a detecção de iOS para o aviso de chamada.

---

## Objetivo

Deixar o painel instalável na tela inicial e entregar Web Push pelo service worker, com um aviso quando o iPhone/iPad ainda não está nesse modo.

---

## Fases no código

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | `public/manifest.json` + ícones em `public/` | ✅ upstream |
| 2 | Bloco condicional em `vueapp.html.erb` | ✅ `DISPLAY_MANIFEST` |
| 3 | `public/sw.js` (`push`, `notificationclick`) | ✅ upstream |
| 4 | Registro e subscription em `pushHelper.js` | ✅ upstream |
| 5 | Envio em `Notification::PushNotificationService` | ✅ upstream |
| 6 | Chaves em `VapidService` | ✅ upstream |
| 7 | `isIosSafariWithoutPwa` + hint na tela de perfil | ✅ fork |
| 8 | Docs em `doc/feature/pwa/` | ✅ |

---

## Detalhe técnico

### 1. Manifesto

`public/manifest.json`:

- `name` / `short_name`: `Chatwoot`
- `start_url`: `/`
- `display`: `standalone`
- `background_color` / `theme_color`: `#2781F6`
- ícones: `/android-icon-36x36.png` até `/android-icon-192x192.png`

`DashboardController::GLOBAL_CONFIG_KEYS` inclui `DISPLAY_MANIFEST`. O layout `vueapp` só emite o `<link rel="manifest">`, os apple-touch-icons e o `theme-color` quando o valor é verdadeiro. O padrão em `config/installation_config.yml` é `true`.

### 2. Service worker

`public/sw.js` não importa biblioteca. No `push`, lê `event.data.json()` e chama `showNotification(title, { tag, data: { url } })`. No clique, fecha o fluxo em `clients.matchAll({ type: 'window' })`.

Não há `skipWaiting`, `clients.claim` nem listener de `fetch`.

### 3. Registro e subscription

`verifyServiceWorkerExistence` sai cedo sem `serviceWorker` ou sem `PushManager`. O registro é `navigator.serviceWorker.register('/sw.js')`.

`registerSubscription` sai cedo sem `window.chatwootConfig.vapidPublicKey`. A subscription pede `userVisibleOnly: true` e manda `endpoint`, `p256dh` e `auth` para `NotificationSubscriptions.create` com `subscription_type: 'browser_push'`.

`App.vue` chama isso dentro de `initializeAccount`, só para reinscrever quem já tem subscription. Quem liga pela primeira vez passa por `NotificationPreferences.onRequestPermissions`.

### 4. Envio

`Notification::PushNotificationService#push_message` manda `title`, `tag` (`<type>_<display_id>_<notification_id>`) e `url` (`app_account_conversation_url`). O body da notificação **não** entra nesse JSON; o worker também não desenha body.

O envio browser exige `VapidService.public_key` e subscription `browser_push`. FCM segue outro método no mesmo service e não usa `sw.js`.

### 5. Aviso iOS (fork)

`custom/app/javascript/dashboard/lib/wavoip/wavoipNotificationEnvironment.js` exporta `isIosSafariWithoutPwa` e `supportsOsNotifications`.

`NotificationPreferences.vue` importa o primeiro e, se for verdadeiro, mostra o parágrafo `PROFILE_SETTINGS.FORM.NOTIFICATIONS.WAVOIP_IOS_PWA_HINT`.

---

## Arquivos

| Arquivo | Papel |
|---------|--------|
| `public/manifest.json` | Manifesto estático |
| `public/sw.js` | Worker de push |
| `public/android-icon-*.png`, `public/apple-icon-*.png` | Ícones citados pelo manifesto e pelo layout |
| `app/views/layouts/vueapp.html.erb` | Link do manifesto, meta tags, chave VAPID no `chatwootConfig` |
| `app/controllers/dashboard_controller.rb` | Expõe `DISPLAY_MANIFEST` |
| `config/installation_config.yml` | Padrão `DISPLAY_MANIFEST: true` |
| `app/javascript/dashboard/helper/pushHelper.js` | Registro do worker e subscription |
| `app/javascript/dashboard/App.vue` | Registra o worker depois da conta |
| `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue` | Liga/desliga push; aviso iOS |
| `app/services/notification/push_notification_service.rb` | Envia o payload |
| `lib/vapid_service.rb` | Lê ou gera `VAPID_KEYS` |
| `workbox-config.js` | Resquício. Não faz parte do build |
| `custom/app/javascript/dashboard/lib/wavoip/wavoipNotificationEnvironment.js` | Detecção de iOS fora do standalone |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | `WAVOIP_IOS_PWA_HINT` |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Mesma chave |

---

## Como testar

1. Com `DISPLAY_MANIFEST` ligado, abrir o painel e confirmar `/manifest.json` e o `<link rel="manifest">` no HTML.
2. Entrar com um agente. No Chrome, Application → Service Workers deve listar `/sw.js` depois da conta carregar.
3. Em Perfil → Notificações, ligar push e aceitar a permissão. A subscription `browser_push` precisa existir para esse usuário.
4. Com a flag push do tipo ligada, disparar uma notificação (mensagem atribuída, por exemplo) com a aba em segundo plano. O sistema mostra o título.
5. O clique abre a conversa da URL do payload.
6. No iPhone/iPad, fora do ícone da tela inicial, a tela de notificações mostra o aviso de instalar o app. Dentro do standalone, o aviso some.

Não esperar página offline, nem o popup da coluna Popup com o app suspenso.

Não rodar o Workbox contra `workbox-config.js`: o `swDest` sobrescreve `public/sw.js` e o push deixa de ter handler.
