# PWA — código, validação e publicação

## Mapa do código

| Caminho | Responsabilidade |
|---------|------------------|
| `custom/app/builders/custom/web_app_manifest_builder.rb` | Identidade, cores, modo standalone e ícones do manifesto |
| `custom/app/controllers/custom/web_app_manifests_controller.rb` | Manifesto público, cache de cinco minutos |
| `custom/app/controllers/custom/notification_workers_controller.rb` | Serve `/notification-worker.js` com `no-cache` |
| `public/sw.js` | Hook mínimo que importa o worker Custom |
| `custom/app/javascript/dashboard/helper/notificationWorker.js` | Exibição, ações, intenções de leitura e recuperação do clique |
| `custom/app/javascript/dashboard/helper/pushHelper.js` | Ambiente, opt-in, sincronização, VAPID, remoção e concorrência |
| `custom/app/javascript/dashboard/helper/{serviceWorker,pushSession,pushResume,pushLogout}.js` | Ativação do registro correto, sessão/cancelamento, retomada e logout |
| `custom/app/javascript/dashboard/helper/{pushDiagnostic,pushPermissionHelp,notificationActions}.js` | Classificação de erros, ajuda de permissão e ações do worker |
| `custom/app/javascript/dashboard/composables/{usePwaInstallation,usePwaInstallPromotion,usePushDevice,usePwaPushInvitation}.js` | Instalação, dispensa, estado Push compartilhado e convite |
| `custom/app/javascript/dashboard/components/pwa/` | `PwaDeviceSettings`, `PwaInstallationCard`, `PwaInstallationHelp`, `PwaMobileInstallPromotion`, `PwaPushInvitation`, `PushPermissionHelp`, `PushDeviceDiagnostics` |
| `custom/app/controllers/custom/api/v1/notification_subscriptions_controller.rb` | Cadastro validado, exclusão por endpoint/`push_token` e teste do dispositivo |
| `custom/app/services/custom/notification/` | `push_notification_service`, `push_test_service`, `push_delivery_recorder`, `browser_push_payload`, `browser_subscription_validator`, `browser_push_log_context`, `delivery_access` |
| `custom/app/builders/custom/notification_subscription_builder.rb` | Grava `last_synced_at` ao criar e ao sincronizar |
| `custom/app/jobs/custom/notification/prune_stale_subscriptions_job.rb` | Remove inscrições browser sem sincronização nem envio aceito em 60 dias |
| `db/migrate/20261024120000_fork_add_push_delivery_state_to_notification_subscriptions.rb` | Colunas anuláveis de sincronização e entrega |
| `custom/vitest.pwa.config.ts` | Setup do Vitest com caminhos relativos ao checkout |
| `bin/fork-pwa-smoke` | Verificação HTTP do release (ver abaixo) |
| `bin/fork-pwa-verify` | Chama o smoke com o SHA de `HEAD`, o nome Se7e e os seis ícones v2 |
| `tests/playwright/tests/e2e/pwa-push.spec.ts` | E2E sob demanda: ativar, sair, entrar e reinscrever, com `subscribe` simulado |
| `ecosystem.config.cjs` | Recusa iniciar o PM2 se `storage` não apontar para o armazenamento persistente |

Hooks upstream `FORK:` e inventário: [current-state.md](./current-state.md#extensão-do-fork). Rode `bin/fork-inventory` quando marcadores mudarem.

Para recompor os maskables a partir dos PNGs regulares, na raiz do projeto, com ImageMagick:

```bash
convert -size 192x192 xc:'#006B98' \( public/brand-assets/pwa-se7e-v2-192.png -resize 80% \) -gravity center -composite public/brand-assets/pwa-se7e-v2-192-maskable.png
convert -size 512x512 xc:'#006B98' \( public/brand-assets/pwa-se7e-v2-512.png -resize 80% \) -gravity center -composite public/brand-assets/pwa-se7e-v2-512-maskable.png
```

## Validação automatizada

### Banco e Redis isolados

O `.env` deste host define `RAILS_ENV=production`. **Nunca rode RSpec sem sobrescrever o ambiente**, para não tocar no banco de produção. Use um banco de teste dedicado e um Redis DB próprio:

```bash
export RAILS_ENV=test POSTGRES_DATABASE=chatwoot_pwa_review_test REDIS_URL=redis://localhost:6379/14
bundle exec rails db:create db:schema:load   # apenas na primeira vez
```

O Ruby 3.4.4 vem do RVM (`rbenv` não está instalado neste host); fora dele, inicialize com `eval "$(rbenv init -)"`.

### Comandos

```bash
bundle exec rspec \
  spec/custom/builders/custom/web_app_manifest_builder_spec.rb \
  spec/custom/controllers/dashboard_controller_spec.rb \
  spec/custom/controllers/custom/web_app_manifests_controller_spec.rb \
  spec/custom/controllers/custom/notification_workers_controller_spec.rb \
  spec/custom/controllers/custom/super_admin/app_configs_controller_spec.rb \
  spec/custom/controllers/custom/api/v1/notification_subscriptions_controller_spec.rb \
  spec/services/notification/push_notification_service_spec.rb \
  spec/custom/services/notification/push_test_service_spec.rb

pnpm exec vitest run --config custom/vitest.pwa.config.ts \
  custom/app/javascript/dashboard/components/pwa \
  custom/app/javascript/dashboard/composables/specs/usePwaInstallation.spec.js \
  custom/app/javascript/dashboard/helper/specs \
  spec/custom/javascript/dashboard/components \
  spec/custom/javascript/dashboard/composables \
  spec/custom/javascript/dashboard/helper

bundle exec rubocop ARQUIVOS_RUBY_ALTERADOS
pnpm exec eslint ARQUIVOS_JS_E_VUE_ALTERADOS
git diff --check
bin/fork-inventory
```

Sempre informe os arquivos de teste ao Vitest: sem filtro, ele executa a suíte inteira do dashboard.

Cobertura: manifesto e `DISPLAY_MANIFEST=false`, dimensões/opacidade/área segura dos PNGs, worker público e sua importação no `sw.js`, cadastro/exclusão browser e FCM com `422`, payload/TTL/urgência/limite de bytes, remoção e preservação de inscrição por tipo de erro, opt-in/opt-out, VAPID, concorrência, diagnóstico de instalação (incluindo timeout), convite, retomada, logout e segurança do worker.

### Resultado da revisão de 24/out/2026

| Verificação | Resultado |
|---|---|
| Vitest (24 arquivos de PWA/Push/notificações) | 224 testes passaram (inclui a localização do aviso genérico do worker e a regressão do logout) |
| RSpec (8 arquivos) | 31 exemplos passaram |
| RuboCop (spec e `bin/fork-pwa-smoke`) e ESLint (worker e specs alterados) | Sem ofensas |
| Build de produção, `bin/fork-pwa-smoke` e aparelhos | **Não executados** nesta revisão |

### Resultado desta branch (24/out/2026)

Números da branch `fix/pwa-push-reinstall` (preferência por usuário, convite de recuperação, chave VAPID, estado de entrega, limpeza e limite). A tabela acima é a revisão anterior do mesmo dia e não foi reexecutada.

| Verificação | Resultado |
|---|---|
| Vitest filtrado (4 arquivos: `browserPush`, `notificationLifecycle`, `usePwaPushInvitation`, `guidedPushPermission`) | 58 testes passaram |
| Regressão sem a correção | Com a chave antiga `false` tratada de novo como recusa, `ignores a legacy false flag that logout used to record` falha (`subscribe` não é chamado). Com a correção, o mesmo exemplo passa |
| RSpec isolado (`RAILS_ENV=test`, banco `chatwoot_pwa_push_reinstall_test`, Redis DB 14) | 44 exemplos, 0 falhas; 2 pendentes porque MFA não está configurado neste ambiente |
| RuboCop (19 arquivos) e ESLint (dashboard JS/Vue/config) | Sem ofensas |
| ESLint do Playwright | 1 aviso `playwright/no-skipped-test`; o spec fica de fora sem `PWA_E2E=1` |
| `git diff --check` | Sem erros |
| `bin/fork-inventory` | 691 marcadores. Novos: helper do Super Admin, duas linhas da view, `config/schedule.yml`, a migration e `bin/fork-pwa-verify` |
| Playwright `pwa-push.spec.ts` | Arquivo listado (1 teste). Não executado: exige `PWA_E2E=1` e o dashboard. Entrega real ao aparelho não foi verificada |
| `bin/fork-pwa-smoke` e aparelhos | **Não executados** |

O exemplo preexistente `spec/controllers/super_admin/user_diagnostics_controller_spec.rb:94` redireciona a segunda requisição para o login do Super Admin neste ambiente, inclusive sem o `include` do helper novo. A página de push com as colunas novas passou no request spec próprio.

Correção de 24/out/2026: o logout gravava `chatwoot_push_enabled=false`, tratado como recusa explícita; relatos de usuários indicavam Push funcionando só na primeira instalação. Os testes de regressão em `notificationLifecycle.spec.js` falham no código anterior. Não foi reproduzido em aparelho.

Na primeira execução, `usePwaInstallation.spec.js` falhava em 7 testes: o composable já chamava `window.matchMedia`, e o spec não o simulava. O spec foi corrigido; o código não mudou.

Evidências por release e dos candidatos anteriores: [relatório de validação](../popup-notifications/validation-report.md).

## Publicação

Merge, push, build, migrations e restart são ações separadas e exigem autorização. Releases futuros seguem o procedimento abaixo, no fork (`cesar-carlos/chatwoot`); nunca crie PR nem faça push para `upstream`.

1. Criar um release isolado a partir de `origin/main` atualizado, sem substituir o checkout em execução. Vincular o armazenamento antes de qualquer tarefa Rails ou do PM2 (seção abaixo).
2. Compilar SDK, assets Rails e dashboard. Fazer backup validado do banco antes de `db:chatwoot_prepare`. A migration de estado de entrega é aditiva e anulável (`last_synced_at`, `last_push_at`, `last_push_status`, `last_push_error`).
3. Preservar `.env`, `DISPLAY_MANIFEST=false`, chaves VAPID e as seis URLs de ícone (Super Admin → Settings → Custom Branding, valores em [current-state.md](./current-state.md#ícones)).
4. Reiniciar web e workers na mesma versão, salvar o estado do PM2 e invalidar HTML, manifestos, `/sw.js`, `/notification-worker.js` e ícones no proxy/CDN. Os seis ícones v2 têm URLs novas; não sobrescrever os arquivos antigos.
5. Rodar `bin/fork-pwa-verify https://DOMINIO` (calcula o SHA de `HEAD` e os seis ícones v2) e conferir a atualização/ativação do worker em um aparelho. Build, troca de release e restart continuam manuais.
6. Manter o release anterior para rollback, usando o mesmo armazenamento compartilhado.
7. Monitorar jobs, `result=accepted/failed/discarded`, inscrições expiradas, timeouts e APIs de ação.

### Uploads persistentes

Este servidor usa `ACTIVE_STORAGE_SERVICE=local`. Todo release deve usar `/root/chatwoot/storage` (ou `CHATWOOT_SHARED_STORAGE_PATH`); `ecosystem.config.cjs` rejeita um release com armazenamento isolado. Em um release novo, sem diretório `storage`:

```bash
ln -s /root/chatwoot/storage storage
node -e "require('./ecosystem.config.cjs')"
```

Se o release já tiver uploads, não remova nem substitua a pasta. Pause web e worker, verifique colisões, copie só os arquivos ausentes para o armazenamento compartilhado, compare os bytes, mova a pasta original para um backup e então crie o vínculo. Depois do deploy, teste pelo domínio público um avatar anterior e um upload recente: manifesto e ícones podem funcionar mesmo quando os uploads retornam 404.

### Smoke público

```bash
bin/fork-pwa-smoke https://chat.se7esistemassinop.com.br \
  GIT_SHA_DO_RELEASE 'Se7e Sistemas Webchat' 'Se7e Sistemas' \
  /brand-assets/pwa-se7e-v2-192.png \
  /brand-assets/pwa-se7e-v2-512.png \
  /brand-assets/pwa-se7e-v2-192-maskable.png \
  /brand-assets/pwa-se7e-v2-512-maskable.png \
  /brand-assets/pwa-se7e-v2-apple-touch-180.png \
  /brand-assets/pwa-se7e-v2-favicon.ico
```

Falha se divergirem: `GIT_SHA` do dashboard, link do manifesto, metadados (`mobile-web-app-capable`, `apple-mobile-web-app-capable`, `theme-color`, Apple Touch, favicon), igualdade entre os dois manifestos, cache público de cinco minutos, identidade white-label, as quatro entradas de ícone, formato/dimensões e bytes dos seis assets contra o release local. Também falha se `/sw.js` não importar `/notification-worker.js` ou divergir de `public/sw.js`, ou se `/notification-worker.js` não for `no-cache` ou divergir dos bytes do release. A verificação do worker foi acrescentada em 24/out/2026 e ainda não rodou contra a produção.

## Homologação manual obrigatória

- Android Chrome/PWA em primeiro plano, segundo plano e encerrada; tela desbloqueada e bloqueada; categorias de notificação diferentes.
- iOS/iPadOS 16.4+ instalado pelo Safari, aberto pelo ícone, fechado e com tela bloqueada; Banners, Foco e Resumo Agendado.
- iOS no Safari ou navegador embutido, confirmando instrução em vez de falso sucesso.
- Desktop, diagnóstico do Super Admin e notificação real de mensagem.
- Clique focando a PWA existente e abrindo a conversa certa; ações **Abrir conversa** e **Marcar como lida**; múltiplas abas.
- Suspender e retomar: reconexão do Action Cable, sincronização das mensagens e atualização da permissão alterada no sistema.
- Logout com Push ativo: o dispositivo não recebe mais notificações do usuário anterior. Troca de conta.
- **Reinstalação:** com Push funcionando, (a) sair, entrar de novo e conferir que o dispositivo volta a receber e que a chave de opt-out não foi gravada; (b) desinstalar a PWA sem sair, reinstalar e conferir; (c) desinstalar marcando e sem marcar a limpeza de dados do site (Chrome desktop/Android); (d) iOS: apagar o ícone, reinstalar pelo Safari e autorizar de novo; (e) usuário afetado pela versão anterior (chave antiga `false`, permissão ainda concedida) vê o convite de recuperação uma única vez, e **Agora não** não grava preferência. Em cada caso, usar **Testar neste dispositivo** e uma mensagem real. O Playwright `pwa-push.spec.ts` cobre ativar, sair e reinscrever com `subscribe` simulado; a entrega real ao aparelho continua manual.
- Chrome Android com manifesto/ícones válidos, mas sem `beforeinstallprompt`: mensagem de indisponibilidade, sem falso erro.
- Teste do dispositivo: fechar com teste pendente, conexão interrompida e restabelecida, conta sem eventos selecionados.
- Teclado, foco e leitor de tela nos diálogos e cartões; rolagem em telas pequenas.

Atalhos antigos podem precisar ser removidos e instalados de novo. No Chrome Android, confirme também que o site não está instalado e que houve interação com a origem.

## Condição para encerrar o rollout

Marque a PWA como pronta somente com a validação HTTP, a suíte automatizada e os cenários manuais concluídos, em um release que contenha o código da `main` atual. Hoje o código está pronto e publicado no fork; falta confirmar o deploy e homologar em Android/iOS.
