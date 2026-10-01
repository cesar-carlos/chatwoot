# PWA — estado atual

A implementação anterior foi publicada no domínio de produção em 30/set/2026. A revisão dos ícones Icon Kitchen está no branch local `fix/pwa-icons-review`, não no `main` nem em produção. A instalação e o Push com o aplicativo fechado ainda precisam de validação em aparelhos reais.

## Arquitetura implementada

| Peça | Comportamento |
|------|---------------|
| Manifesto | Controller e builder públicos em `custom/`; resposta `application/manifest+json`, cache público de cinco minutos |
| URLs | `/manifest.webmanifest` é canônica; `/manifest.json` entrega o mesmo conteúdo por compatibilidade |
| Identidade | `id`, `start_url` e `scope` em `/`; `name` de `INSTALLATION_NAME`; `short_name` de `BRAND_NAME` |
| Instalação | `display: standalone`, `prefer_related_applications: false`, tema `#2781F6` |
| Ícones no candidato | `PWA_ICON_192_URL` e `PWA_ICON_URL` para `any`; `PWA_ICON_192_MASKABLE_URL` e `PWA_ICON_MASKABLE_URL` para `maskable`; `PWA_APPLE_TOUCH_ICON_URL` e `PWA_FAVICON_URL` para HTML |
| HTML | Manifesto, `theme-color`, Apple Touch 180×180, favicon e metadados Apple independem de `DISPLAY_MANIFEST` |
| Interface | Componente Vue customizado apresenta disponível, instalado, instruções iOS, indisponível, incompatível e erros verificáveis de manifesto/ícone |
| Push | Helper customizado controla opt-in local, inscrição, remoção, concorrência, troca da chave VAPID, logout e sincronização ao retomar a página |
| Backend | Controllers e serviços estendidos por `prepend_mod_with`; o core contém apenas hooks/imports marcados com `FORK:` |
| Worker | Valida payload, mostra título/corpo/ícone/tag e reutiliza apenas janela do painel na mesma origem |

O arquivo estático `public/manifest.json` foi removido. Não há cache offline, polling em segundo plano nem tentativa de manter o WebSocket ativo durante a suspensão.

Os seis novos assets ficam em `/brand-assets/pwa-se7e-v2-*`, sem sobrescrever as URLs antigas que podem estar em cache por cerca de um ano. Os PNGs maskable usam o símbolo original reduzido a 80% sobre o fundo azul `#006B98`, mantendo os pixels claros dentro do círculo central de raio igual a 40% da largura. O arquivo legado `public/apple-touch-icon.png`, antes vazio, também foi preenchido. As URLs novas só aparecerão no manifesto e no HTML após configurar os seis valores no Super Admin; instalações que deixarem as novas opções vazias mantêm o formato anterior do manifesto.

## Comportamento por plataforma

- Chromium: o app captura `beforeinstallprompt`, exibe o botão somente quando o navegador oferece instalação e chama `prompt()` apenas após clique. `appinstalled` atualiza o estado.
- iOS/iPadOS: fora do modo standalone, a interface orienta Safari → Compartilhar → Adicionar à Tela de Início. A inscrição Push fica desabilitada até o app ser aberto pelo ícone.
- Desktop: a mesma PWA e o mesmo fluxo Push continuam disponíveis sem alterar o comportamento do Action Cable.
- Retomada: ao voltar ao primeiro plano, a inscrição Push é revalidada sem polling em segundo plano; a tela de preferências recebe o estado atualizado.
- Logout: o cliente tenta cancelar a inscrição no servidor e no navegador antes de encerrar a sessão, sem registrar um novo worker. A exclusão remota tem limite de dez segundos; uma falha de limpeza não bloqueia o logout, mas é registrada sem expor o endpoint.

## Estado da produção observado

Antes do deploy em 30/set/2026, `chat.se7esistemassinop.com.br` ainda informava `GIT_SHA=61fc65923d`, sem manifesto dinâmico e sem os ícones Se7e. Após o deploy, a verificação pública retornou:

| Verificação | Resultado observado |
|-------------|---------------------|
| Release do dashboard | `GIT_SHA=6e30bc8c97f18bd559cf38c998b4f40b5ca49354` |
| `/manifest.webmanifest` | `200 application/manifest+json`, cache público de cinco minutos |
| `/manifest.json` | `200 application/manifest+json`, alias do manifesto dinâmico |
| Link `rel="manifest"` no HTML | Presente mesmo com `DISPLAY_MANIFEST=false` |
| `/brand-assets/pwa-icon-se7e-192.png` | `200 image/png` |
| `/brand-assets/pwa-icon-se7e-512.png` | `200 image/png` |
| `/sw.js` | `200 text/javascript` |

O verificador antigo passou para o release `6e30bc8c97`. O manifesto público inclui identidade white-label e os dois ícones antigos. O verificador atualizado exige quatro entradas no manifesto e seis assets versionados; ele só deve ser executado após o novo deploy e a configuração. Respostas HTTP corretas não substituem o teste de instalação no navegador.

Web e worker rodam via PM2 no worktree isolado do release `6e30bc8c97`, com configuração persistida para reboot. `db:chatwoot_prepare` aplicou nove migrações pendentes; uma verificação posterior não encontrou migrações restantes. `PWA_ICON_192_URL` e `PWA_ICON_URL` apontam para os PNGs Se7e, `DISPLAY_MANIFEST=false` foi mantido e as chaves VAPID não foram alteradas. Dois backups do banco anteriores à migração foram preservados. O checkout principal `/root/chatwoot` continua antigo e com arquivos locais, mas não é o diretório em execução.

## Validação do código

- ESLint direcionado e RuboCop dos arquivos alterados passaram em 30/set/2026.
- Os 19 testes Vitest de Push, instalação, worker e preferências passaram com a configuração `custom/vitest.pwa.config.ts`, que resolve os setup files dentro do worktree.
- A revisão Icon Kitchen valida dimensões e opacidade de cinco PNGs, a integridade do ICO e ausência de pixels claros fora da área segura nos dois maskables derivados dos ícones regulares.
- No candidato de release reconciliado, 18 exemplos RSpec passaram em sete arquivos, usando `chatwoot_pwa_release_test` e Redis DB 14 isolados. O Ruby 3.4.4 está disponível via RVM; `rbenv` não está instalado.
- RuboCop passou nos 22 arquivos Ruby alterados, e ESLint passou nos JS/Vue alterados. O build Vite de produção passou após incorporar todas as alterações locais, incluindo a correção de sintaxe de `ConversationCard.vue`.
- O comando `bin/fork-pwa-smoke` passou no domínio público após o deploy do commit `6e30bc8c97`.

Na revisão Icon Kitchen local atual, 16 exemplos RSpec de manifesto/HTML/branding/ícones e 29 testes Vitest de PWA/Push passaram. ESLint e RuboCop direcionados, `git diff --check`, inventário `FORK:` e build Vite de produção também passaram. O verificador HTTP atualizado ainda não pode passar no domínio público, porque a revisão não foi publicada nem configurada.

O release anterior permanece em execução. O candidato de novos ícones precisa ser integrado, publicado e configurado antes da homologação final em aparelhos reais.

## Critério de aceite

O domínio público ainda entrega ambos os manifestos com os dois ícones anteriores. Após o novo deploy, verificar as quatro entradas e os seis assets; o Chrome Android deve oferecer **Instalar** e abrir o painel sem barras do navegador. No iOS/iPadOS 16.4+, a instalação pela Tela de Início deve abrir em standalone. Uma mensagem elegível deve gerar Push com a PWA fechada, e o clique deve reutilizar a PWA aberta ou criar uma janela na conversa correta. Os critérios de aparelho e entrega final de Push ainda não foram homologados.
