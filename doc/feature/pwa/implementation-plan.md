# PWA — implementação, testes e publicação

## Código implementado

| Caminho | Responsabilidade |
|---------|------------------|
| `custom/app/builders/custom/web_app_manifest_builder.rb` | Identidade, cores, modo standalone e ícones do manifesto |
| `custom/app/controllers/custom/web_app_manifests_controller.rb` | Resposta pública e cache de cinco minutos |
| `custom/app/javascript/dashboard/composables/usePwaInstallation.js` | Eventos e estados de instalação |
| `custom/app/javascript/dashboard/components/pwa/PwaDeviceSettings.vue` | Interface de instalação e Push por dispositivo |
| `custom/app/javascript/dashboard/helper/pushHelper.js` | Ambiente, opt-in, sincronização, VAPID, remoção e concorrência |
| `custom/app/controllers/custom/api/v1/notification_subscriptions_controller.rb` | Exclusão autenticada por endpoint ou `push_token` |
| `custom/app/services/custom/notification/push_notification_service.rb` | Payload, TTL, urgência, remoção expirada e logs sem PII |
| `custom/app/services/custom/notification/push_test_service.rb` | Diagnóstico com o mesmo formato do Push real |
| `public/sw.js` | Exibição e clique seguro da notificação |
| `custom/vitest.pwa.config.ts` | Setup de testes PWA isolado no worktree |
| `bin/fork-pwa-smoke` | Verificação HTTP do release, manifesto e bytes dos seis ícones públicos |

A revisão Icon Kitchen acrescenta quatro PNGs de manifesto (192/512 regulares e maskable), Apple Touch 180×180 e favicon ICO em URLs versionadas. O arquivo `/apple-touch-icon.png`, anteriormente vazio, passa a conter o ícone Apple. As novas configurações são opcionais para preservar instalações existentes, mas as seis devem ser preenchidas para ativar a identidade Se7e v2.

Os pontos upstream foram limitados aos hooks/imports necessários no controller da API, serviços, layout, bootstrap do dashboard e preferências.

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

Os specs existentes cobrem manifesto e `DISPLAY_MANIFEST=false`, dimensões/opacidade dos PNGs, exclusão browser/FCM e parâmetros 422, payload/TTL/urgência, expiração, opt-in/opt-out, VAPID, falhas parciais, concorrência, instalação guiada e segurança do worker.

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

Na revisão Icon Kitchen local, os specs direcionados de manifesto/HTML/branding, 20 testes Vitest de PWA/Push, ESLint e RuboCop direcionados, `git diff --check` e o build Vite de produção passaram. O próximo release ainda requer verificação HTTP e teste em aparelhos após publicação.

## Publicação no fork

1. A PWA anterior foi integrada ao `origin/main` de `cesar-carlos/chatwoot` com o histórico 4.18 e publicada em 30/set/2026 no commit `6e30bc8c97`. A revisão Icon Kitchen ainda não foi integrada. Não criar PR nem push para `upstream`.
2. O deploy anterior usou um worktree isolado, sem substituir o checkout principal antigo. Fazer a nova integração e publicação também por worktree isolado.
3. Para a revisão Icon Kitchen, integrar o branch validado ao `main` do fork, gerar uma imagem limpa do novo release e executar `db:chatwoot_prepare` para criar as quatro configurações adicionais. Não alterar a produção antes da imagem e do banco estarem na mesma versão.
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
   curl -fsS https://DOMINIO/app/login | rg 'manifest|apple-mobile-web-app|theme-color'
   curl -fsS https://DOMINIO/manifest.webmanifest | jq '{id,name,short_name,display,prefer_related_applications,icons}'
   curl -fsS https://DOMINIO/manifest.json | jq '{id,name,icons}'
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-192.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-512.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-192-maskable.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-512-maskable.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-apple-touch-180.png
   curl -I https://DOMINIO/brand-assets/pwa-se7e-v2-favicon.ico
   ```

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

O comando retorna erro se a versão, o HTML, os dois manifestos, o cache, a identidade white-label, o formato/dimensões ou os bytes dos seis assets públicos divergirem do release local. A versão anterior do verificador passou no domínio público em 30/set/2026 com `GIT_SHA=6e30bc8c97f18bd559cf38c998b4f40b5ca49354`; a versão atual só poderá passar após o novo deploy. Execute-a como etapa obrigatória após cada deploy da PWA.

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

Atalhos antigos podem precisar ser apagados e instalados novamente. No Chrome Android, confirmar também que o site não está instalado, que houve interação com a origem e que o navegador ofereceu `beforeinstallprompt`; a ausência do botão interno isoladamente não comprova que o manifesto está inválido.

## Condição para encerrar o rollout

Marcar a PWA como pronta somente quando a validação HTTP, a suíte automatizada e os cenários manuais estiverem concluídos. Em 1º/out/2026, a revisão dos ícones ainda não está integrada ou publicada; a homologação em Android/iOS e a entrega final de Push também permanecem pendentes.
