# PWA — estado atual

Implementação integrada ao `main` do fork e publicada no domínio de produção em 30/set/2026. A entrega HTTP está verificada; a instalação e o Push com o aplicativo fechado ainda precisam de validação em aparelhos reais.

## Arquitetura implementada

| Peça | Comportamento |
|------|---------------|
| Manifesto | Controller e builder públicos em `custom/`; resposta `application/manifest+json`, cache público de cinco minutos |
| URLs | `/manifest.webmanifest` é canônica; `/manifest.json` entrega o mesmo conteúdo por compatibilidade |
| Identidade | `id`, `start_url` e `scope` em `/`; `name` de `INSTALLATION_NAME`; `short_name` de `BRAND_NAME` |
| Instalação | `display: standalone`, `prefer_related_applications: false`, tema `#2781F6` |
| Ícones | `PWA_ICON_192_URL` e `PWA_ICON_URL`; PNGs Se7e empacotados em 192×192 e 512×512, opacos e destinados a `any maskable` |
| HTML | Manifesto, `theme-color`, `apple-touch-icon` e metadados Apple independem de `DISPLAY_MANIFEST` |
| Interface | Componente Vue customizado apresenta disponível, instalado, instruções iOS, indisponível e incompatível |
| Push | Helper customizado controla opt-in local, inscrição, remoção, concorrência e troca da chave VAPID |
| Backend | Controllers e serviços estendidos por `prepend_mod_with`; o core contém apenas hooks/imports marcados com `FORK:` |
| Worker | Valida payload, mostra título/corpo/ícone/tag e aceita somente navegação para a mesma origem |

O arquivo estático `public/manifest.json` foi removido. Não há cache offline, polling em segundo plano nem tentativa de manter o WebSocket ativo durante a suspensão.

## Comportamento por plataforma

- Chromium: o app captura `beforeinstallprompt`, exibe o botão somente quando o navegador oferece instalação e chama `prompt()` apenas após clique. `appinstalled` atualiza o estado.
- iOS/iPadOS: fora do modo standalone, a interface orienta Safari → Compartilhar → Adicionar à Tela de Início. A inscrição Push fica desabilitada até o app ser aberto pelo ícone.
- Desktop: a mesma PWA e o mesmo fluxo Push continuam disponíveis sem alterar o comportamento do Action Cable.

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

O teste `bin/fork-pwa-smoke` passou para o release `6e30bc8c97`. O manifesto público inclui identidade white-label e os dois ícones declarados. Isso remove a falha HTTP que impedia a instalação, mas não substitui o teste de instalação no navegador.

Web e worker rodam via PM2 no worktree isolado do release `6e30bc8c97`, com configuração persistida para reboot. `db:chatwoot_prepare` aplicou nove migrações pendentes; uma verificação posterior não encontrou migrações restantes. `PWA_ICON_192_URL` e `PWA_ICON_URL` apontam para os PNGs Se7e, `DISPLAY_MANIFEST=false` foi mantido e as chaves VAPID não foram alteradas. Dois backups do banco anteriores à migração foram preservados. O checkout principal `/root/chatwoot` continua antigo e com arquivos locais, mas não é o diretório em execução.

## Validação do código

- ESLint direcionado e RuboCop dos arquivos alterados passaram em 30/set/2026.
- Os 19 testes Vitest de Push, instalação, worker e preferências passaram com a configuração `custom/vitest.pwa.config.ts`, que resolve os setup files dentro do worktree.
- O spec dos ícones agora afirma a área segura `maskable`. Uma verificação direta com MiniMagick confirmou dimensões, opacidade e conteúdo dentro da área segura nos dois PNGs.
- No candidato de release reconciliado, 18 exemplos RSpec passaram em sete arquivos, usando `chatwoot_pwa_release_test` e Redis DB 14 isolados. O Ruby 3.4.4 está disponível via RVM; `rbenv` não está instalado.
- RuboCop passou nos 22 arquivos Ruby alterados, e ESLint passou nos JS/Vue alterados. O build Vite de produção passou após incorporar todas as alterações locais, incluindo a correção de sintaxe de `ConversationCard.vue`.
- O comando `bin/fork-pwa-smoke` passou no domínio público após o deploy do commit `6e30bc8c97`.

O release unificado está em execução. Falta confirmar em aparelhos reais a instalação standalone, o Push com a PWA fechada, o clique na conversa e a reconexão ao retomar.

## Critério de aceite

O domínio público já entrega ambos os manifestos com os dois ícones. O Chrome Android deve oferecer **Instalar** e abrir o painel sem barras do navegador. No iOS/iPadOS 16.4+, a instalação pela Tela de Início deve abrir em standalone. Uma mensagem elegível deve gerar Push com a PWA fechada, e o clique deve reutilizar a PWA aberta ou criar uma janela na conversa correta. Em 30/set/2026, os critérios de aparelho e entrega final de Push ainda não estavam homologados.
