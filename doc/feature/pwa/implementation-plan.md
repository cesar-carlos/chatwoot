# PWA — implementação, testes e publicação

## Revisão final do candidato assistido

Entrega local em `fix/pwa-assisted-diagnostics-review`, criada de `origin/main` atualizado e acrescida por fast-forward do candidato mobile. Mantém as alterações anteriores e não altera main ou produção.

Implementados: cancelamento real de manifesto/ícones após dez segundos, consulta compartilhada com progresso e retry explícito; proteção de diagnóstico após fechamento/desmontagem; atividade Push compartilhada; motivos específicos de ambiente indisponível; aviso de inscrição sem eventos, condicionado à consulta da conta e com link acessível. Componentes e lógica permanecem em `custom/`; preferências upstream recebem apenas dois hooks mínimos.

Novas regressões ficam em `spec/custom/javascript/dashboard`: validação de instalação, ambiente Push, orientação do dispositivo e integração das flags por conta, além dos specs ampliados de diagnóstico/composable. [Comandos e resultados](../popup-notifications/validation-report.md#revisão-do-candidato--02out2026).

Ainda necessário: homologar fechamento com teste pendente, conexão interrompida/restabelecida, conta sem eventos, troca de conta, teclado/foco/leitor de tela e instalação/Push real em desktop, Android e iOS/iPadOS. Merge, publicação, build e deploy exigem autorização separada; não há migration prevista.

## Incremento de instalação mobile e teste assistido

Branch de entrega: `feat/mobile-pwa-install-diagnostics`, criada de `origin/main` após fetch e acrescida por fast-forward de `feat/guided-push-permission`. Merge, publicação e deploy não fazem parte desta entrega.

Novos componentes/composable/helper ficam em `custom/app/javascript/dashboard`: `PwaMobileInstallPromotion`, `PwaInstallationCard`, `PwaInstallationHelp`, `PushDeviceDiagnostics`, `usePwaInstallPromotion` e `pushDiagnostic`. O único hook de dashboard novo é import/registro/montagem em `App.vue`, marcado `FORK:`. `usePushDevice` e `usePwaInstallation` concentram as operações; `PwaDeviceSettings` passa a reutilizar os componentes.

Na instalação, prompt nativo exige evento capturado e clique; cada evento é consumido uma vez. Ajuda manual não promete instalação automática. Erros de manifesto/ícones impedem o CTA direto. Dispensa por usuário permanece independente do opt-out.

No teste, negar permissão, iOS fora da PWA, opt-out ou inscrição não confirmada impede envio. Recuperação/ativação só se tornam teste após novo clique explícito. A resposta deve conter `accepted: true`; códigos HTTP têm mensagens próprias e não provocam retries nem novos prompts.

Executar Vitest/ESLint direcionados e inventário; evidências e comando completo no [relatório](../popup-notifications/validation-report.md#instalação-mobile-e-teste-assistido--02out2026). Homologar teclado/foco/leitor de tela, rolagem mobile, instalação real, desbloqueio e Push com app fechado em Chrome/Edge, Android e iOS/iPadOS. Futuro build/deploy precisa de autorização e release isolado com storage compartilhado.

## Ativação guiada no candidato

Implementação isolada em `feat/guided-push-permission`, baseada em `origin/main` atualizado e preservando o commit local de documentação do deploy. Sem merge/publicação/deploy nesta etapa.

O componente `PwaPushInvitation.vue`, a ajuda `PushPermissionHelp.vue` e os composables `usePushDevice.js`/`usePwaPushInvitation.js` ficam em `custom/`. O dashboard recebe apenas import, registro e montagem marcados `FORK:`. O diálogo do design system recebe nome acessível pelo título; Vitest inclui os specs frontend de `spec/custom/javascript`.

Validar convite único, opt-out, permissão pendente/negada/concedida, concorrência, fechamento, sessão encerrada, recuperação por foco e escolha explícita dos eventos. Não solicitar autorização nativa no carregamento. Cenários em aparelhos, teclado/leitor de tela e layout real continuam necessários.

A futura publicação exige autorização separada, novo build de JS/Vue e release isolado com storage compartilhado. Nenhuma migration ou troca de VAPID está prevista. Evidências: [relatório](../popup-notifications/validation-report.md#ativação-guiada--candidato-de-02out2026).

## Código implementado

| Caminho | Responsabilidade |
|---------|------------------|
| `custom/app/builders/custom/web_app_manifest_builder.rb` | Identidade, cores, modo standalone e ícones do manifesto |
| `custom/app/controllers/custom/web_app_manifests_controller.rb` | Resposta pública e cache de cinco minutos |
| `custom/app/javascript/dashboard/composables/usePwaInstallation.js` | Eventos e estados de instalação |
| `custom/app/javascript/dashboard/components/pwa/PwaDeviceSettings.vue` | Interface de instalação e Push por dispositivo |
| `custom/app/javascript/dashboard/helper/pushHelper.js` | Ambiente, opt-in, sincronização, VAPID, remoção e concorrência |
| `custom/app/javascript/dashboard/helper/serviceWorker.js` | Ativação do registro correto com timeout de dez segundos |
| `custom/app/javascript/dashboard/helper/pushSession.js` | Geração da sessão, cancelamento e proteção contra respostas tardias |
| `custom/app/javascript/dashboard/helper/pushResume.js` | Revalidação do Push na retomada e atualização da interface |
| `custom/app/javascript/dashboard/helper/pushLogout.js` | Limpeza da inscrição do dispositivo antes do logout |
| `custom/app/controllers/custom/api/v1/notification_subscriptions_controller.rb` | Exclusão autenticada por endpoint ou `push_token` |
| `custom/app/services/custom/notification/push_notification_service.rb` | Payload, TTL, urgência, remoção expirada e logs sem PII |
| `custom/app/services/custom/notification/push_test_service.rb` | Diagnóstico com o mesmo formato do Push real |
| `public/sw.js` | Hook mínimo para importar o worker Custom |
| `custom/app/javascript/dashboard/helper/notificationWorker.js` | Exibição, ações, criação pendente e recuperação do clique |
| `custom/vitest.pwa.config.ts` | Setup de testes PWA isolado no worktree |
| `bin/fork-pwa-smoke` | Verificação HTTP do release, manifesto e bytes dos seis ícones públicos |
| `ecosystem.config.cjs` | Validação de storage persistente antes de iniciar web e worker no host |

A revisão Icon Kitchen acrescenta quatro PNGs de manifesto (192/512 regulares e maskable), Apple Touch 180×180 e favicon ICO em URLs versionadas. Os maskables foram derivados dos ícones regulares, reduzidos a 80% sobre o fundo azul, e o teste exige que nenhum pixel claro essencial ultrapasse a área segura. O arquivo `/apple-touch-icon.png`, anteriormente vazio, passa a conter o ícone Apple. As novas configurações são opcionais para preservar instalações existentes, mas as seis devem ser preenchidas para ativar a identidade Se7e v2.

Para reproduzir somente os maskables a partir dos PNGs regulares fornecidos, no diretório raiz do projeto, com ImageMagick:

```bash
convert -size 192x192 xc:'#006B98' \( public/brand-assets/pwa-se7e-v2-192.png -resize 80% \) -gravity center -composite public/brand-assets/pwa-se7e-v2-192-maskable.png
convert -size 512x512 xc:'#006B98' \( public/brand-assets/pwa-se7e-v2-512.png -resize 80% \) -gravity center -composite public/brand-assets/pwa-se7e-v2-512-maskable.png
```

Os pontos upstream foram limitados aos hooks/imports necessários no controller da API, serviços, layout, bootstrap do dashboard e preferências.

## Revisão de entrega do candidato

As correções de `fix/notification-delivery-hardening` são separadas dos releases já publicados. Não há migration prevista, nem alteração de VAPID, manifesto ou ícones.

Antes do envio, `Custom::Notification::DeliveryAccess` revalida vínculo com conta ativa, `NotificationPolicy#access?` e `ConversationPolicy#show?`. Preferência ausente/desativada descarta o envio, sem compor corpo/título. A API valida HTTPS absoluto sem credenciais e chaves: ponto P-256 não comprimido/on-curve de 65 bytes e segredo de 16 bytes; Base64 e Base64URL permanecem aceitos. Dados inválidos recebem `422` antes do builder, sem gravação/transferência parcial. Cadastro e exclusão FCM permanecem compatíveis.

`pushSession.js` invalida a geração ao iniciar logout e cancela requisições HTTP. Cada etapa assíncrona confere a sessão antes de inscrição, sync, opt-in e publicação de estado. A limpeza do logout não fica na fila: tenta unsubscribe local mesmo se a exclusão remota falhar e limita o total a dez segundos. O registro correto deve estar ativo antes de `subscribe()`, também com limite de dez segundos. Não se usa apenas uma corrida de Promises sem cancelamento.

O payload real mantém título/corpo/ícone/tag/URL, TTL de 24 horas e urgência alta e adiciona IDs de usuário, conta e notificação e rótulos das ações. Diagnósticos não têm ações de leitura. Clique recupera navegação/foco rejeitados ou cliente desaparecido abrindo nova janela na mesma origem. Eventos de leitura e ações: [Pop-up](../popup-notifications/implementation-plan.md).

### Publicação autorizada e procedimento de atualização

1. Integração, publicação no fork e build/deploy foram concluídos no release `f58ca95d4d`. Para atualizações futuras, repetir o procedimento isolado abaixo após autorização. Evidências do deploy: [validation-report.md](../popup-notifications/validation-report.md).
2. Preparar release isolado, preservar `.env`, ícones, `DISPLAY_MANIFEST=false`, VAPID e `storage` compartilhado. Validar PM2 antes de iniciar.
3. Reiniciar web/workers e invalidar HTML, manifestos, `/sw.js`, `/notification-worker.js` e ícones no proxy/CDN.
4. Verificar GIT_SHA, manifestos, ícones, import do worker e `200 application/javascript` no overlay. Conferir atualização/ativação no aparelho.
5. Executar mensagem real e diagnóstico; homologar instalação, tela bloqueada, clique, ações, múltiplas abas e logout. Manter release anterior para rollback.

Monitorar jobs, `result=accepted/failed/discarded`, inscrições expiradas, falhas/timeouts e APIs de ações. Logs não contêm e-mail, conteúdo, tokens ou endpoint completo. Evidências e comandos: [validation-report.md](../popup-notifications/validation-report.md).

## Validação automatizada

Executar a partir do worktree, inicializando rbenv antes dos comandos Ruby:

```bash
eval "$(rbenv init -)"
bundle exec rspec \
  spec/custom/builders/custom/web_app_manifest_builder_spec.rb \
  spec/custom/controllers/dashboard_controller_spec.rb \
  spec/custom/controllers/custom/web_app_manifests_controller_spec.rb \
  spec/custom/controllers/custom/super_admin/app_configs_controller_spec.rb \
  spec/custom/controllers/custom/api/v1/notification_subscriptions_controller_spec.rb \
  spec/services/notification/push_notification_service_spec.rb \
  spec/custom/services/notification/push_test_service_spec.rb
bundle exec rubocop ARQUIVOS_RUBY_ALTERADOS
pnpm exec vitest run --config custom/vitest.pwa.config.ts ARQUIVOS_DE_TESTE_PWA_E_PUSH
pnpm exec eslint ARQUIVOS_JS_E_VUE_ALTERADOS
git diff --check
bin/fork-inventory
```

Os specs existentes cobrem manifesto e `DISPLAY_MANIFEST=false`, dimensões/opacidade/área segura dos PNGs, exclusão browser/FCM e parâmetros 422, payload/TTL/urgência, expiração, opt-in/opt-out, VAPID, falhas parciais, concorrência, diagnóstico de instalação, limpeza no logout, retomada da PWA e segurança do worker.

### Histórico da revisão publicada em 30/set/2026

| Verificação | Estado em 30/set/2026 |
|-------------|-----------------------|
| ESLint direcionado | Passou com a configuração isolada do worktree |
| Vitest direcionado | 19 testes passaram em quatro arquivos |
| RSpec direcionado | 18 exemplos passaram em sete arquivos no candidato de release, com banco e Redis isolados |
| RuboCop direcionado | 18 arquivos Ruby alterados, sem infrações |
| `git diff --check` | Sem erros |
| Área segura dos ícones antigos | Asserção adicionada; ambos os PNGs antigos confirmados por execução direta de MiniMagick |

O build Vite de produção passou no candidato anterior com as 27 alterações locais. ESLint passou nos JS/Vue alterados e RuboCop nos 22 arquivos Ruby alterados. Antes daquela publicação, as migrations foram ensaiadas em uma cópia isolada do banco; no deploy, as nove migrations pendentes foram aplicadas em produção. O ambiente dispõe de Ruby 3.4.4 via RVM, mas não de `rbenv`. Esses resultados não validam automaticamente a revisão Icon Kitchen.

Antes da publicação Icon Kitchen, 16 exemplos RSpec de manifesto/HTML/branding/ícones e 29 testes Vitest de PWA/Push passaram. ESLint e RuboCop direcionados, `git diff --check`, `bin/fork-inventory` e o build Vite de produção também passaram. A verificação HTTP após o deploy está registrada abaixo; os testes em aparelhos continuam pendentes.

## Publicação no fork

1. A PWA e a revisão Icon Kitchen foram integradas ao `origin/main` de `cesar-carlos/chatwoot`. O release anterior `6e30bc8c97` continua disponível para rollback. Não criar PR nem push para `upstream`.
2. O release anterior `05361df464` foi preparado em um worktree isolado, sem substituir o checkout principal ou o release anterior. Vincular o storage persistente antes de executar tarefas Rails ou iniciar os processos, conforme a seção abaixo.
3. O build de produção passou; um backup do banco foi validado antes de executar `db:chatwoot_prepare`. Não havia migrações pendentes; a tarefa criou as quatro configurações adicionais.
4. Em Super Admin → Settings → Custom Branding, definir:
   - `PWA_ICON_192_URL=/brand-assets/pwa-se7e-v2-192.png`
   - `PWA_ICON_URL=/brand-assets/pwa-se7e-v2-512.png`
   - `PWA_ICON_192_MASKABLE_URL=/brand-assets/pwa-se7e-v2-192-maskable.png`
   - `PWA_ICON_MASKABLE_URL=/brand-assets/pwa-se7e-v2-512-maskable.png`
   - `PWA_APPLE_TOUCH_ICON_URL=/brand-assets/pwa-se7e-v2-apple-touch-180.png`
   - `PWA_FAVICON_URL=/brand-assets/pwa-se7e-v2-favicon.ico`
   - manter `DISPLAY_MANIFEST=false` no white-label.
5. Preservar as chaves VAPID atuais e reiniciar web e workers na mesma versão.
6. Invalidar HTML, `/manifest.json`, `/manifest.webmanifest` e `/sw.js` no proxy/CDN. Os seis ícones v2 usam novas URLs; não sobrescrever os arquivos de ícone antigos, que podem estar em cache em aparelhos já instalados.
7. Verificar pelo domínio público:

   ```bash
   curl -fsS https://DOMINIO/app/login | rg 'manifest|mobile-web-app|theme-color'
   curl -fsS https://DOMINIO/manifest.webmanifest | jq '{id,name,short_name,display,prefer_related_applications,icons}'
   curl -fsS https://DOMINIO/manifest.json | jq '{id,name,icons}'
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-192.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-512.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-192-maskable.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-512-maskable.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-apple-touch-180.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-favicon.ico
   ```

### Uploads persistentes em releases do host

Este servidor usa `ACTIVE_STORAGE_SERVICE=local`. Cada release deve usar o mesmo diretório persistente `/root/chatwoot/storage`; a configuração PM2 rejeita um release com storage isolado. `CHATWOOT_SHARED_STORAGE_PATH` permite declarar outro diretório persistente ao carregar a configuração PM2.

Em um worktree de release novo, sem diretório `storage` existente, preparar o vínculo antes de executar tarefas Rails:

```bash
ln -s /root/chatwoot/storage storage
node -e "require('./ecosystem.config.cjs')"
```

Se já houver uploads no release, não remover nem substituir a pasta diretamente. Pausar web e worker, verificar colisões, copiar somente arquivos ausentes para o storage compartilhado, comparar os bytes, mover a pasta original para um backup e então criar o vínculo. Reiniciar ambos os processos e salvar o estado do PM2. Usar o mesmo storage também no rollback.

Além do smoke da PWA, testar pelo domínio público um avatar anterior ao deploy e um upload recente. O manifesto e os ícones podem funcionar mesmo quando os uploads dos contatos retornam 404.

### Verificação automática do release

Após publicar e configurar os ícones, substitua `GIT_SHA_DO_RELEASE` pelo SHA da imagem publicada:

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

O comando retorna erro se a versão, o HTML, os dois manifestos, o cache, a identidade white-label, o formato/dimensões ou os bytes dos seis assets públicos divergirem do release local. O HTML deve incluir tanto `mobile-web-app-capable` quanto `apple-mobile-web-app-capable`. Ele passou após o hotfix em 01/out/2026 com `GIT_SHA=05361df464372e27ccc3634687162cf179f0f38c`. Execute-o após cada deploy da PWA.

### Hotfix de uploads e metadados em 01/out/2026

- Storage compartilhado restaurado após preservar 251 arquivos novos, sem colisões ou diferenças SHA-256; a pasta original permanece em `.codex/backups/storage_60ee71940d_before_shared_20261001`.
- Os 8.137 avatares do diagnóstico voltaram a estar acessíveis; as quatro fotos do incidente retornaram HTTP 200.
- Release `05361df464` acrescenta o metadado genérico solicitado pelo Chromium e a validação de storage na configuração PM2. `bin/fork-inventory` passa a incluir essa configuração.
- O código frontend e os ícones não mudaram neste hotfix; os assets já compilados do release anterior foram reutilizados. Não houve nova migração ou alteração de VAPID.
- No release final, 8.138 avatares estavam acessíveis, com HTTP 200 em quatro fotos antigas e uma recente. Dois RSpec de HTML, sete Vitest de instalação, lint direcionado, smoke público e validação dos dois estados do storage passaram.
- O aviso de banner suprimido por `preventDefault()` permanece esperado: a instalação é apresentada após o clique em **Instalar**.

### Publicação de 01/out/2026

- Release `60ee71940d` em web e Sidekiq via PM2, com estado salvo para reboot; o release `6e30bc8c97` e o dump anterior permanecem disponíveis para rollback.
- `db:chatwoot_prepare` criou as quatro configurações Icon Kitchen; não havia migrações pendentes. As seis URLs foram configuradas, mantendo `DISPLAY_MANIFEST=false` e as chaves VAPID existentes.
- Build de produção, 67 Vitest e 69 RSpec direcionados passaram. Os RSpec detectaram um hook ausente no builder de Pop-up; a correção entrou no release antes da troca de processos.
- Login público, manifestos, service worker e os seis assets corresponderam ao release; `bin/fork-pwa-smoke` passou.
- Instalação e Push real com a PWA fechada ainda não foram homologados em Android/iOS. O sucesso HTTP ou dos testes automatizados não comprova a apresentação da notificação pelo aparelho.

### Publicação de 30/set/2026

- Assets de produção compilados e nove migrations aplicadas após ensaio em banco-clone; dois backups anteriores à migração foram preservados.
- `PWA_ICON_192_URL` e `PWA_ICON_URL` configurados com os PNGs Se7e; `DISPLAY_MANIFEST=false` e as chaves VAPID foram preservados.
- Web e worker reiniciados pelo PM2 no mesmo worktree de release; o estado do PM2 foi salvo para reboot.
- Login, manifestos, service worker e ícones responderam pelo domínio público; o verificador automático da PWA passou.
- Não foi feita homologação em aparelho nem confirmação de exibição de Push com a PWA fechada. Caches de clientes e atalhos antigos podem exigir atualização ou reinstalação.

## Validação manual obrigatória

- Android Chrome/PWA em primeiro plano, segundo plano e encerrada.
- iOS/iPadOS 16.4+ instalado pelo Safari, fechado e com tela bloqueada.
- iOS no Safari ou navegador embutido, confirmando instrução em vez de falso sucesso.
- Desktop, diagnóstico do Super Admin e notificação real de mensagem.
- Clique focando a PWA existente e abrindo a conversa correta.
- Suspender e retomar, confirmando reconexão do Action Cable e sincronização das mensagens.
- Alterar a permissão Push no sistema enquanto a PWA está suspensa e confirmar que a tela atualiza ao voltar.
- Sair da conta com Push ativo e confirmar que o dispositivo não recebe mais notificações do usuário anterior.
- Testar o Chrome Android com manifesto e ícones válidos, mas sem `beforeinstallprompt`, verificando a mensagem de indisponibilidade sem falso diagnóstico de erro.

Atalhos antigos podem precisar ser apagados e instalados novamente. No Chrome Android, confirmar também que o site não está instalado, que houve interação com a origem e que o navegador ofereceu `beforeinstallprompt`; a ausência do botão interno isoladamente não comprova que o manifesto está inválido.

## Condição para encerrar o rollout

Marcar a PWA como pronta somente quando a validação HTTP, a suíte automatizada e os cenários manuais estiverem concluídos. Em 01/out/2026, o código e os ícones estão publicados, mas a homologação em Android/iOS e a confirmação de Push real com a PWA fechada permanecem pendentes.
