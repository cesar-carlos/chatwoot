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
| `bin/fork-pwa-smoke` | Verificação HTTP do release, manifesto e PNGs públicos |

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

### Estado da última revisão

| Verificação | Estado em 30/set/2026 |
|-------------|-----------------------|
| ESLint direcionado | Passou com a configuração isolada do worktree |
| Vitest direcionado | 19 testes passaram em quatro arquivos |
| RSpec direcionado | 18 exemplos passaram em sete arquivos no candidato de release, com banco e Redis isolados |
| RuboCop direcionado | 18 arquivos Ruby alterados, sem infrações |
| `git diff --check` | Sem erros |
| Área segura dos ícones | Asserção adicionada; ambos os PNGs confirmados por execução direta de MiniMagick |

O build Vite de produção também passou no candidato de release após aplicar a correção de sintaxe de `ConversationCard.vue` já existente no checkout ativo. O ambiente dispõe de Ruby 3.4.4 via RVM, mas não de `rbenv`.

## Publicação no fork

1. Integração Git concluída no `origin/main` de `cesar-carlos/chatwoot` até o commit `4254116ffd`. Não criar PR nem push para `upstream`.
2. Os 12 commits da PWA já foram aplicados ao `main` de produção no worktree isolado `fix/pwa-production-release`; os specs e o build passaram. Antes de publicá-lo, decidir como preservar as 27 alterações locais do checkout ativo, inclusive a correção de sintaxe necessária ao build. Não substituir o checkout em execução por `origin/main` diretamente.
3. Gerar uma imagem limpa do release reconciliado e executar `db:chatwoot_prepare` para criar `PWA_ICON_192_URL` e `PWA_ICON_URL` nas configurações.
4. Em Super Admin → Settings → Custom Branding, definir:
   - `PWA_ICON_192_URL=/brand-assets/pwa-icon-se7e-192.png`
   - `PWA_ICON_URL=/brand-assets/pwa-icon-se7e-512.png`
   - manter `DISPLAY_MANIFEST=false` no white-label.
5. Preservar as chaves VAPID atuais e reiniciar web e workers na mesma versão.
6. Remover artefatos estáticos antigos do release e invalidar HTML, `/manifest.json`, `/manifest.webmanifest`, `/sw.js` e os dois ícones no proxy/CDN.
7. Verificar pelo domínio público:

   ```bash
   curl -fsS https://DOMINIO/app/login | rg 'manifest|apple-mobile-web-app|theme-color'
   curl -fsS https://DOMINIO/manifest.webmanifest | jq '{id,name,short_name,display,prefer_related_applications,icons}'
   curl -fsS https://DOMINIO/manifest.json | jq '{id,name,icons}'
   curl -I https://DOMINIO/brand-assets/pwa-icon-se7e-192.png
   curl -I https://DOMINIO/brand-assets/pwa-icon-se7e-512.png
   ```

### Verificação automática do release

Após publicar e configurar os ícones, substitua `GIT_SHA_DO_RELEASE` pelo SHA da imagem publicada:

```bash
bin/fork-pwa-smoke https://chat.se7esistemassinop.com.br \
  GIT_SHA_DO_RELEASE 'Se7e Sistemas Webchat' 'Se7e Sistemas' \
  /brand-assets/pwa-icon-se7e-192.png \
  /brand-assets/pwa-icon-se7e-512.png
```

O comando retorna erro se a versão, o HTML, os dois manifestos, o cache, a identidade white-label ou as dimensões e o tipo dos PNGs públicos divergirem. Em 30/set/2026, ele falha no `GIT_SHA` porque o domínio ainda serve `61fc65923d`. Execute-o como etapa obrigatória após cada deploy da PWA.

## Validação manual obrigatória

- Android Chrome/PWA em primeiro plano, segundo plano e encerrada.
- iOS/iPadOS 16.4+ instalado pelo Safari, fechado e com tela bloqueada.
- iOS no Safari ou navegador embutido, confirmando instrução em vez de falso sucesso.
- Desktop, diagnóstico do Super Admin e notificação real de mensagem.
- Clique focando a PWA existente e abrindo a conversa correta.
- Suspender e retomar, confirmando reconexão do Action Cable e sincronização das mensagens.

Atalhos antigos podem precisar ser apagados e instalados novamente.

## Condição para encerrar o rollout

Marcar a PWA como pronta somente quando a validação HTTP, a suíte automatizada e os cenários manuais estiverem concluídos. Em 30/set/2026, o código estava integrado, mas o deploy e a homologação permaneciam pendentes.
