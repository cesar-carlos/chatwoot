# PWA — estado atual e arquitetura

Descreve o código da `main` na revisão de 24/out/2026. Para o estado de publicação, ver [README](./README.md#estado).

## Manifesto e HTML

| Peça | Comportamento |
|------|---------------|
| Manifesto | `Custom::WebAppManifestsController` (público) e `Custom::WebAppManifestBuilder`; `application/manifest+json`, cache público de cinco minutos |
| URLs | `/manifest.webmanifest` é canônica; `/manifest.json` entrega o mesmo conteúdo. Não existe arquivo estático concorrente |
| Identidade | `id`, `start_url` e `scope` em `/`; `name` de `INSTALLATION_NAME`; `short_name` de `BRAND_NAME` (com fallback para o nome) |
| Instalação | `display: standalone`, `prefer_related_applications: false`, tema e fundo `#2781F6` |
| HTML | `vueapp.html.erb` declara manifesto, `theme-color`, Apple Touch, favicon e os dois metadados de web app independentemente de `DISPLAY_MANIFEST` |
| Service worker | `public/sw.js` importa `/notification-worker.js`, servido por `Custom::NotificationWorkersController` com `Cache-Control: no-cache` |

Não há cache offline, polling em segundo plano nem tentativa de manter o WebSocket ativo durante a suspensão.

### Ícones

| Configuração (Super Admin → Custom Branding) | Uso | Valor em produção |
|---|---|---|
| `PWA_ICON_192_URL` | Manifesto, `any` 192 | `/brand-assets/pwa-se7e-v2-192.png` |
| `PWA_ICON_URL` | Manifesto, `any` 512; ícone do Push | `/brand-assets/pwa-se7e-v2-512.png` |
| `PWA_ICON_192_MASKABLE_URL` | Manifesto, `maskable` 192 | `/brand-assets/pwa-se7e-v2-192-maskable.png` |
| `PWA_ICON_MASKABLE_URL` | Manifesto, `maskable` 512 | `/brand-assets/pwa-se7e-v2-512-maskable.png` |
| `PWA_APPLE_TOUCH_ICON_URL` | `apple-touch-icon` 180×180 | `/brand-assets/pwa-se7e-v2-apple-touch-180.png` |
| `PWA_FAVICON_URL` | `rel="icon"` do HTML | `/brand-assets/pwa-se7e-v2-favicon.ico` |

Os padrões de `PWA_ICON_192_URL`/`PWA_ICON_URL` (`/android-icon-192x192.png`, `/favicon-512x512.png`) existem em `public/`. As quatro configurações opcionais vêm vazias. Sem os ícones maskable, o manifesto mantém uma entrada `any maskable` por tamanho; com eles, declara `any` e `maskable` separados.

Os maskables foram derivados dos ícones regulares: símbolo reduzido a 80% sobre o fundo `#006B98`, com os pixels claros dentro do círculo central de raio igual a 40% da largura (coberto por teste pixel a pixel). Os arquivos v2 usam URLs novas e não sobrescrevem as antigas, que podem estar em cache por cerca de um ano. O `public/apple-touch-icon.png` raiz, antes vazio, foi preenchido.

## Instalação

- **Chromium:** `usePwaInstallation` guarda `beforeinstallprompt` sem abrir UI. O botão **Instalar** só aparece com um prompt utilizável e chama `prompt()` por clique; cada evento é consumido uma única vez e eventos novos são preservados. `appinstalled` e modo standalone marcam o app como instalado.
- **iOS/iPadOS:** não há o evento; a interface ensina Safari → Compartilhar → Adicionar à Tela de Início (incluindo **Abrir como App**, quando disponível). Push fica desabilitado até abrir pelo ícone.
- **Navegadores integrados conhecidos** (Facebook, Instagram, Line, WebView): oferecem cópia do endereço da origem, sem parâmetros privados.
- **Validação do manifesto:** sem o evento, o painel verifica manifesto e PNGs 192/512 da mesma origem, com um `AbortController` de dez segundos para toda a operação. JSON/campos inválidos ou ícones ausentes são erros de configuração; rede, HTTP 5xx e timeout têm mensagens próprias e não são tratados como configuração inválida. **Verificar novamente** exige clique; não há polling.
- **Promoção mobile:** `PwaMobileInstallPromotion` exige autenticação, conta carregada/ativa, Android/iOS e ausência de standalone/instalação confirmada. A dispensa fica em `chatwoot:install-promotion:v1:<user_id>`, separada do convite Push e do opt-out. Armazenamento indisponível suprime a promoção; as preferências continuam acessíveis. Desktop recebe a mesma ajuda nas preferências.

## Push por dispositivo

- **Opt-in por usuário:** `chatwoot:push-enabled:v1:<uid>` guarda a escolha de quem está na sessão (`uid` do cookie `cw_d_session_info`, só neste aparelho). Sem `uid` legível, não há preferência. A chave antiga `chatwoot_push_enabled=true` ainda conta como opt-in; o `false` antigo é ignorado, porque misturava logout com recusa. Gravações novas usam só a chave por usuário. No carregamento, uma inscrição optada que sumiu é recriada e sincronizada. Operações são serializadas.
- **Rotação VAPID:** com chave nova, a inscrição antiga é removida remotamente (quando possível), cancelada localmente e recriada. A chave pública usada fica em `chatwoot:push-vapid:v1`. Se o navegador não expõe `applicationServerKey`, a inscrição é mantida quando não há registro ou quando o registro coincide; só uma chave gravada diferente força a recriação.
- **Worker correto:** o registro de `/sw.js` (com `updateViaCache: 'none'`) precisa estar ativo antes de `subscribe()`, com limite de dez segundos; `navigator.serviceWorker.ready` de outro escopo não basta.
- **Sessão e logout:** `pushSession` invalida a geração ao iniciar logout e cancela requisições; cada etapa assíncrona confere a sessão antes de inscrever, sincronizar, gravar opt-in ou publicar estado. A limpeza tenta remoção local e remota em paralelo, sem registrar worker novo, limitada a dez segundos; falhas não bloqueiam o logout nem expõem o endpoint. O logout **não grava opt-out** e não altera nenhuma chave de preferência. Só **desativar neste dispositivo** grava `false` na chave do usuário atual. Depois de sair e entrar de novo, a inscrição é recriada se essa chave (ou o `true` antigo) estiver presente.
- **Retomada:** ao voltar ao primeiro plano, `pushResume` revalida permissão e inscrição, sem polling durante a suspensão.
- **Estado compartilhado:** `usePushDevice` concentra **Verificando / Ativando / Testando / Desativando** entre convite, preferências e diagnóstico. `getPushEnvironment` mantém o contrato `unsupported` e acrescenta `reason` (contexto inseguro, APIs ausentes, VAPID ausente).
- **Preferências por conta:** consultadas por conta, com erro/retry e gravação bloqueada até o sucesso. Dispositivo inscrito, consulta bem-sucedida e zero eventos Push geram um aviso com link para a seção de eventos; os eventos nunca são marcados automaticamente.

### Convite e ajuda de permissão

`usePwaPushInvitation` abre um convite na primeira abertura autenticada da PWA instalada (standalone, conta ativa, ambiente suportado), depois do onboarding, da consulta da inscrição e de outros diálogos. Oferece **Permitir notificações**, **Ativar neste dispositivo** ou **Como liberar notificações**, conforme a permissão real.

- A solicitação nativa só ocorre após clique. **Agora não**, Escape e fechamento externo não alteram preferências nem criam inscrição.
- `chatwoot:push-invitation:v1:<user_id>` guarda só a apresentação local; não vai ao servidor, não contém credenciais e não altera o opt-out. Limpar o armazenamento pode reapresentar o convite; armazenamento indisponível suprime o convite.
- Opt-out explícito na chave do usuário atual, ou inscrição ativa, suprimem o convite. O `false` antigo não suprime. Permissão negada mostra ajuda Chrome/Edge, Android, iOS/PWA ou genérica; o app não consegue desbloqueá-la.
- **Recuperação única:** na PWA, com conta ativa, permissão `granted`, status `unsubscribed`, chave antiga `false`, chave nova ausente e `chatwoot:push-recovery:v1:<user_id>` ainda vazio, o mesmo diálogo mostra `PUSH_RECOVERY_DESCRIPTION` (en/pt_BR). A chave de recuperação é gravada antes de abrir. **Agora não** não muda preferências. Ativar grava a chave nova `true`. Quem nunca viu o convite normal continua no fluxo de `chatwoot:push-invitation:v1`.
- Foco/visibilidade e **Já liberei, verificar novamente** reavaliam a permissão. Bloqueado → concedido pode concluir a inscrição, respeitando opt-out. Permissão concedida só para Pop-up não cria inscrição Push.

### Teste neste dispositivo

`usePushDevice.test`/`inspect` revalidam ambiente, permissão e opt-out antes e depois de cada espera, confirmam a inscrição pelo helper e enviam usando esse endpoint. `PushDeviceDiagnostics` mostra:

| Resultado | Comportamento |
|---|---|
| Aceito | Pergunta **Recebi / Não recebi / Recebi som ou aviso, mas não apareceu banner** |
| **Não recebi** | Confere novamente os itens locais, sem reenviar; itens válidos levam a orientações de sistema/Foco, sem afirmar bloqueio detectado |
| **Som sem banner** | Revalida sem enviar; orienta categoria Android ou Banners/Foco/Resumo Agendado no iOS |
| Permissão negada, iOS fora da PWA, opt-out, inscrição não confirmada | Não envia; abre a ajuda correspondente |
| HTTP 401/403 · 404 · 422 · 429 · 502 · rede · timeout | Mensagens próprias (`pushDiagnostic`): sessão/autorização · reativar o dispositivo · cadastro · aguardar · provedor · conexão. Falhas de transporte não são atribuídas à permissão |

Fechar o diálogo invalida a apresentação pendente: uma resposta tardia não o reabre. Um teste já aceito pelo provedor ainda pode chegar ao aparelho. Não há telemetria de confirmação de banner.

## Worker de notificação

`notificationWorker.js` (em `custom/`, sem credenciais nem chamadas autenticadas):

- **Payload:** JSON inválido ou sem título gera um aviso genérico sem conteúdo, em vez de Push silencioso (o WebKit exige apresentação visível e pode revogar a inscrição). Se a apresentação normal falha, tenta uma mínima (`display_failed`). O texto genérico é localizado no próprio worker, que não tem i18n: português se `navigator.language` começa com `pt`, inglês nos demais casos.
- **Navegação:** URLs externas ou inválidas viram a raiz da própria origem. Somente uma janela do painel (`/app`) da mesma origem é reutilizada, preferindo a da mesma conta; navegação/foco rejeitados ou cliente desaparecido levam a uma nova janela na conversa.
- **Ações:** **Abrir conversa** e **Marcar como lida** só aparecem em avisos reais (usuário, conta e notificação válidos, e URL da mesma conta), limitadas a `Notification.maxActions`. **Marcar como lida** cria uma intenção de uso único em memória, válida por 60 segundos; o frontend aguarda a sessão, consome a intenção com `postMessage` e confere o destinatário e a conta. Sem login ou após expirar/reiniciar o worker, não há escrita. A ação abre a caixa de entrada para não marcar outras notificações via last-seen da conversa.
- **Leituras:** mensagens `notifications-read` fecham avisos exibidos ou ainda pendentes que correspondam ao recibo.

## Backend

- **Cadastro (`POST /api/v1/notification_subscriptions`)**: valida tipo (`browser_push`/`fcm`) e, para browser, endpoint HTTPS absoluto sem credenciais, chave P-256 não comprimida (ponto válido de 65 bytes) e segredo de 16 bytes; Base64 e Base64URL aceitos. Dados inválidos recebem `422` antes de qualquer gravação. FCM permanece compatível.
- **Exclusão (`DELETE`)**: exatamente um entre `endpoint` e `push_token`; remove browser ou FCM do usuário atual.
- **Teste (`POST …/test`)**: só envia ao endpoint browser do próprio usuário (`404` se inexistente), no máximo três em qualquer janela de 60 segundos por usuário (`browser-push-test:<user_id>`, `expire` no primeiro incremento, `429` acima disso), `200` quando aceito e `502` quando o provedor recusa. Não cria notificação real.
- **Envio:** `Custom::Notification::DeliveryAccess` revalida vínculo com conta ativa, `NotificationPolicy#access?` e `ConversationPolicy#show?`; preferência ausente ou desativada descarta o envio antes de compor conteúdo. O payload preserva título, corpo, ícone, tag, URL, IDs de usuário/conta/notificação e rótulos das ações, com TTL de 24 horas e urgência alta. O serviço real e o diagnóstico usam o mesmo JSON, limitado a 3.900 bytes: só título (até 120 caracteres) e corpo são reduzidos, em UTF-8; metadados excessivos falham explicitamente.
- **Falhas do provedor:** inscrição inválida/expirada é removida; falha de autenticação (VAPID) **não** remove a inscrição; limite de taxa, rede e demais erros são registrados. Os logs trazem provedor classificado, HTTP/motivo de uma lista permitida e IDs, sem e-mail, conteúdo, tokens nem endpoint completo.
- **Estado da inscrição:** `notification_subscriptions` ganha `last_synced_at` (o aparelho confirmou o cadastro), `last_push_at`, `last_push_status` (`accepted`, `failed`, `expired`) e `last_push_error` (classe, HTTP e motivo já classificado). `PushDeliveryRecorder` grava com `update_columns`. O builder Custom atualiza `last_synced_at` ao criar e ao sincronizar de novo.
- **Limpeza:** `Custom::Notification::PruneStaleSubscriptionsJob`, diário, remove `browser_push` quando `COALESCE(last_synced_at, created_at)` tem mais de 60 dias e não houve envio `accepted` nesse período. Quem recebe envio aceito recente permanece. FCM não entra. O log traz só a contagem. Um aparelho removido volta a se inscrever no próximo uso se a preferência local for `true`.
- **Super Admin:** a tabela de dispositivos mostra provedor, última sincronização e último envio (status, hora, erro resumido).
- **Regra de time sem agente:** evento **Uma conversa foi atribuída ao seu time e está sem agente atribuído**, com seleção Push independente por conta e desmarcada por padrão. Reutiliza inscrição, worker e payload; não altera instalação. Semântica e proteções de idempotência: [Pop-up — estado atual](../popup-notifications/current-state.md).

## Extensão do fork

A lógica vive em `custom/`. Controllers e serviços Ruby usam `prepend_mod_with`; os arquivos upstream mantêm só hooks e imports mínimos marcados `FORK:` (`config/routes.rb`, `vueapp.html.erb`, `dashboard_controller.rb`, `App.vue`, `NotificationPreferences.vue`, `app/services/notification/push_notification_service.rb`, `notification_subscriptions_controller.rb`, `installation_config.yml`, `public/sw.js`). Os hooks foram conferidos após o merge do upstream 4.19.1.

## Comportamento por plataforma

| Plataforma | Instalação | Push |
|---|---|---|
| Chromium desktop/Android | Botão **Instalar** com o evento; senão, menu do navegador | Inscrição na aba ou na PWA instalada, separadas |
| iOS/iPadOS 16.4+ | Safari → Compartilhar → Adicionar à Tela de Início | Somente após abrir pelo ícone (standalone) |
| Navegador integrado | Copiar endereço e abrir no Chrome/Safari | Instalar pelo Chrome/Safari antes de ativar |
