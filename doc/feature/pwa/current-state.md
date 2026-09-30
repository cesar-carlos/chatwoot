# PWA — estado atual

Inventário em 30/set/2026. O código do branch e a instalação publicada têm estados diferentes.

## Código no branch `fix/pwa-mobile-push`

| Peça | Comportamento |
|------|---------------|
| Layout do painel | Aponta sempre para `/manifest.webmanifest`, mesmo com `DISPLAY_MANIFEST=false` |
| Manifesto | Resposta pública `application/manifest+json`, cache de cinco minutos e alias `/manifest.json` |
| Identidade | `id`, `start_url` e `scope` em `/`; nome vindo de `INSTALLATION_NAME`, nome curto de `BRAND_NAME` |
| Ícones | `PWA_ICON_192_URL` e `PWA_ICON_URL` declaram PNGs de 192×192 e 512×512; padrões `/android-icon-192x192.png` e `/favicon-512x512.png` |
| Aparência | `display: standalone`, cor `#2781F6`; `DISPLAY_MANIFEST` controla apenas metadados e ícones padrão do Chatwoot no HTML |
| Service worker | `/sw.js` mostra título, corpo, ícone e tag do Push; no clique, foca e navega uma janela da mesma origem ou abre outra |
| Inscrição Push | Revalida a inscrição existente com permissão concedida; a solicitação de permissão ocorre após interação do usuário |
| Preferências | Push do sistema e Pop-up com painel aberto são explicados separadamente; iOS fora do app instalado recebe instruções |

Não há cache offline do painel, polling em segundo plano nem tentativa de manter o WebSocket ativo quando o sistema suspende a página. O registro do service worker ocorre após o carregamento da conta; nas versões atuais do Chrome, um handler `fetch` não é requisito de instalação. O worker continua necessário para Web Push.

## Produção observada em 30/set/2026

No domínio da captura (`chat.se7esistemassinop.com.br`), a inspeção pública mostrou:

| Verificação | Resultado |
|-------------|-----------|
| `DISPLAY_MANIFEST` no HTML de `/app/login` | `false` |
| Link `rel="manifest"` nesse HTML | Ausente |
| `GET /manifest.webmanifest` | 404 |
| `GET /manifest.json` | 200, manifesto estático com nome `Chatwoot` e ícones até 192×192 |
| `GET /favicon-512x512.png` | 200, mas o ícone não é declarado no manifesto publicado |

Esses dados explicam o aviso **“Não é possível instalar o app”** do Chrome: a página não associa manifesto e o manifesto disponível não contém o ícone 512×512 exigido para a promoção de instalação. O menu **Criar atalho** não comprova instalação da PWA.

O manifesto antigo e o service worker publicados tinham `Cache-Control` de aproximadamente um ano. No deploy, confirmar a remoção do arquivo estático antigo do diretório servido pelo proxy e invalidar caches de HTML, manifesto e worker.

## Critério de aceite no aparelho

Após a publicação, o HTML deve incluir `/manifest.webmanifest`; os dois endpoints de manifesto devem responder 200 com os ícones 192×192 e 512×512 acessíveis como `image/png`. No Android Chrome, o menu deve permitir **Instalar** e o ícone deve abrir uma janela standalone. No iOS, a instalação é feita pelo Safari em **Adicionar à Tela de Início**. A entrega de Push com a PWA fechada é uma validação separada.
