# PWA — Improvements backlog

Itens fora do shell que já está no repositório em 29/set/2026.

---

## Já no código

- Manifesto `standalone` em `/manifest.json`
- Ícones e `theme-color` no layout, atrás de `DISPLAY_MANIFEST`
- `public/sw.js` com `push` e `notificationclick`
- Registro em `pushHelper.js` depois que a conta carrega
- Web Push VAPID em `Notification::PushNotificationService`
- Aviso `WAVOIP_IOS_PWA_HINT` quando o iOS não está em standalone

---

## P2 — Instalação

| ID | Item | Notas |
|----|------|-------|
| PWA-P2-1 | Ícone 512×512 no manifesto | O Chrome pede 192 e 512 para o critério de instalável. Hoje o maior é 192 |
| PWA-P2-2 | Meta `apple-mobile-web-app-capable` | O layout não declara. Ajuda o iOS a abrir sem a UI do Safari |
| PWA-P2-3 | Nome e cor da instalação | O JSON está fixo em “Chatwoot” / `#2781F6`. Uma instalação com outra marca continua com esse nome no ícone |
| PWA-P2-4 | `start_url` do painel | Hoje é `/`. O agente cai na raiz em vez de `/app` |
| PWA-P2-5 | Registrar o worker antes do login | Sem worker na tela de login, o critério de instalável do Chrome fica incompleto até a conta carregar |

## P3 — Não fazer sem desenho novo

| ID | Item | Notas |
|----|------|-------|
| PWA-P3-1 | Ligar o `workbox-config.js` | O destino é `public/sw.js`. Gerar esse arquivo apaga o handler de push |
| PWA-P3-2 | Cache offline do dashboard | O painel depende de API e Action Cable. Cache de shell sem regra de sessão entrega HTML velho |
| PWA-P3-3 | Prompt “Instalar app” | Não há `beforeinstallprompt`. Só vale a pena com ícone 512 e worker estável |
