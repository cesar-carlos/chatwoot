# PWA — implementação e publicação

Registro do que foi implementado no branch `fix/pwa-mobile-push` em 30/set/2026. As verificações de produção abaixo ainda precisam ocorrer após o deploy.

## Código

| Arquivo | Responsabilidade |
|---------|------------------|
| `custom/app/builders/custom/web_app_manifest_builder.rb` | Monta identidade, cores e os ícones 192×192 e 512×512 |
| `custom/app/controllers/custom/web_app_manifests_controller.rb` | Serve o manifesto público com `application/manifest+json` e cache de cinco minutos |
| `config/routes.rb` | Expõe `/manifest.webmanifest` e o alias `/manifest.json` |
| `app/views/layouts/vueapp.html.erb` | Inclui o link do manifesto fora do bloco `DISPLAY_MANIFEST` |
| `config/installation_config.yml` | Define `PWA_ICON_192_URL` e `PWA_ICON_URL` |
| `custom/app/controllers/custom/super_admin/app_configs_controller.rb` | Expõe as duas URLs em Custom Branding |
| `public/brand-assets/pwa-icon-se7e-192.png` e `pwa-icon-se7e-512.png` | Ícones PNG quadrados da marca Se7e |
| `public/sw.js` | Exibe Push e navega até a conversa no clique |
| `app/javascript/dashboard/helper/pushHelper.js` | Inscrição, sincronização e remoção de Push por dispositivo |
| `app/services/notification/push_notification_service.rb` | Envia título, corpo, ícone, tag e URL, com TTL de 24 horas e urgência alta |

O antigo `public/manifest.json` foi removido do branch. O mesmo JSON dinâmico atende às duas URLs. O manifesto usa `id`, `start_url` e `scope` em `/` para preservar a identidade da instalação. `name` vem de `INSTALLATION_NAME`; `short_name` usa `BRAND_NAME`, com fallback para o nome da instalação. `DISPLAY_MANIFEST=false` continua ocultando metadados e ícones padrão do Chatwoot no HTML, mas não a PWA.

As configurações têm padrões funcionais (`/android-icon-192x192.png` e `/favicon-512x512.png`). Para a marca Se7e, configurar explicitamente as duas URLs após publicar o código.

## Publicação

1. Integrar e publicar os commits da PWA a partir do fork, com web e workers na mesma versão. Executar o preparo padrão `db:chatwoot_prepare` para criar as novas `InstallationConfig`.
2. Em Super Admin → Settings → Custom Branding, definir `PWA_ICON_192_URL=/brand-assets/pwa-icon-se7e-192.png` e `PWA_ICON_URL=/brand-assets/pwa-icon-se7e-512.png`. Manter `DISPLAY_MANIFEST=false` se a instalação usa white-label.
3. Garantir que o arquivo estático antigo `public/manifest.json` não permaneça no diretório servido pelo Nginx. Invalidar os caches de HTML, `/manifest.json`, `/manifest.webmanifest`, `/sw.js` e dos ícones no proxy/CDN. O manifesto antigo observado em produção tinha cache público de aproximadamente um ano.
4. Reiniciar web e workers e verificar pelo domínio público, incluindo o HTML de `/app/login`:

   ```bash
   curl -fsS https://DOMINIO/app/login | rg 'rel="manifest"'
   curl -fsS https://DOMINIO/manifest.webmanifest | jq '{id,name,short_name,display,icons}'
   curl -fsS https://DOMINIO/manifest.json | jq '{id,name,icons}'
   curl -I https://DOMINIO/brand-assets/pwa-icon-se7e-192.png
   curl -I https://DOMINIO/brand-assets/pwa-icon-se7e-512.png
   ```

   Ambos os manifestos devem responder 200 com `Content-Type: application/manifest+json`, declarar ícones 192×192 e 512×512 e apontar para PNGs acessíveis na mesma origem.

5. No Chrome Android, abrir a página no navegador, usar **Instalar** e confirmar que o ícone abre uma janela standalone. Em iOS/iPadOS 16.4+, abrir no Safari, adicionar à Tela de Início e iniciar pelo ícone; atalhos antigos podem exigir remoção e nova instalação.
6. Em cada plataforma, testar permissão Push por interação do usuário, diagnóstico de Push, uma mensagem real com o app fechado e o clique abrindo a conversa. Confirmar separadamente que o Pop-up só aparece com o painel aberto e que o painel sincroniza ao retornar do segundo plano.

## Validação automatizada

Os testes do manifesto cobrem o conteúdo white-label, os dois tamanhos, as rotas públicas, o tipo de resposta e o link com `DISPLAY_MANIFEST=false`. Executar os specs de `spec/custom/builders/custom/web_app_manifest_builder_spec.rb`, `spec/custom/controllers/custom/web_app_manifests_controller_spec.rb`, `spec/custom/controllers/custom/super_admin/app_configs_controller_spec.rb` e `spec/controllers/dashboard_controller_spec.rb`, além de RuboCop nos Ruby alterados e `bin/fork-inventory`.

Nenhum teste automatizado garante que um Chrome específico exibirá **Instalar**: essa decisão também depende do navegador, do estado de instalação e de o deploy entregar os arquivos corretos. O painel não implementa navegação offline; o worker não tem handler `fetch`.
