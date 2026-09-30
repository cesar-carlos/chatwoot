# PWA — estado atual

Implementação integrada ao `origin/main` do fork até o commit `4254116ffd`, em 30/set/2026. Esse é o estado do repositório, não uma confirmação de publicação em produção.

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

Em 30/set/2026, `chat.se7esistemassinop.com.br` ainda informava `GIT_SHA=61fc65923d` e apresentava o estado abaixo:

| Verificação | Resultado observado |
|-------------|---------------------|
| `/manifest.webmanifest` | `404` |
| `/manifest.json` | `200 application/json`, conteúdo estático com nome Chatwoot e ícones somente até 192×192 |
| Link `rel="manifest"` no HTML | Ausente |
| `/brand-assets/pwa-icon-se7e-192.png` | `404` |
| `/brand-assets/pwa-icon-se7e-512.png` | `404` |

Esse estado explica o aviso **Não é possível instalar o app**. A correção só se torna efetiva após publicar uma imagem limpa do commit `092c8eeaf7` ou posterior, executar a preparação das configurações e invalidar os caches.

O web e o worker de produção rodam via PM2 a partir de `/root/chatwoot`. Em 30/set/2026, o `main` desse checkout tinha 480 commits exclusivos, o branch PWA tinha 292 commits exclusivos em relação a ele, e havia 27 caminhos alterados ou não rastreados no checkout de produção. Publicar diretamente o branch PWA descartaria mudanças que existem apenas no código em execução; reconciliar os históricos e preservar as alterações locais é pré-requisito do deploy.

## Validação do código

- ESLint direcionado e RuboCop dos arquivos alterados passaram em 30/set/2026.
- Os 19 testes Vitest de Push, instalação, worker e preferências passaram com a configuração `custom/vitest.pwa.config.ts`, que resolve os setup files dentro do worktree.
- O spec dos ícones agora afirma a área segura `maskable`. Uma verificação direta com MiniMagick confirmou dimensões, opacidade e conteúdo dentro da área segura nos dois PNGs.
- No candidato de release reconciliado, 18 exemplos RSpec passaram em sete arquivos, usando `chatwoot_pwa_release_test` e Redis DB 14 isolados. O Ruby 3.4.4 está disponível via RVM; `rbenv` não está instalado.
- RuboCop passou nos 18 arquivos Ruby alterados. O build Vite de produção passou após incorporar ao candidato a correção de sintaxe já presente como alteração local no checkout de produção.
- O comando `bin/fork-pwa-smoke` detectou corretamente que o domínio ainda serve o commit `61fc65923d`.

Ainda falta decidir como preservar as demais alterações locais do checkout ativo, publicar o release reconciliado e confirmar o comportamento em aparelhos reais. O candidato isolado `fix/pwa-production-release` não foi publicado nem substituiu o código em execução.

## Critério de aceite

O domínio público deve entregar ambos os manifestos com os dois ícones. O Chrome Android deve oferecer **Instalar** e abrir o painel sem barras do navegador. No iOS/iPadOS 16.4+, a instalação pela Tela de Início deve abrir em standalone. Uma mensagem elegível deve gerar Push com a PWA fechada, e o clique deve reutilizar a PWA aberta ou criar uma janela na conversa correta. Em 30/set/2026, esses critérios ainda não estavam homologados em produção.
