# PWA — estado atual

Inventário final do branch `fix/pwa-mobile-push` em 30/set/2026.

## Arquitetura implementada

| Peça | Comportamento |
|------|---------------|
| Manifesto | Controller e builder públicos em `custom/`; resposta `application/manifest+json`, cache público de cinco minutos |
| URLs | `/manifest.webmanifest` é canônica; `/manifest.json` entrega o mesmo conteúdo por compatibilidade |
| Identidade | `id`, `start_url` e `scope` em `/`; `name` de `INSTALLATION_NAME`; `short_name` de `BRAND_NAME` |
| Instalação | `display: standalone`, `prefer_related_applications: false`, tema `#2781F6` |
| Ícones | `PWA_ICON_192_URL` e `PWA_ICON_URL`; PNGs Se7e validados em 192×192 e 512×512, opacos e dentro da área segura |
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

## Estado da produção observado antes da publicação

Em 30/set/2026, `chat.se7esistemassinop.com.br` ainda não entregava `/manifest.webmanifest`, não ligava o manifesto ao HTML quando `DISPLAY_MANIFEST=false` e servia um `/manifest.json` estático com ícones até 192×192. Esse estado explica o aviso **Não é possível instalar o app** e deve desaparecer somente após deploy e invalidação dos caches.

## Critério de aceite

O domínio público deve entregar ambos os manifestos com os dois ícones. O Chrome Android deve oferecer **Instalar** e abrir o painel sem barras do navegador. No iOS/iPadOS 16.4+, a instalação pela Tela de Início deve abrir em standalone. Uma mensagem elegível deve gerar Push com a PWA fechada, e o clique deve reutilizar a PWA aberta ou criar uma janela na conversa correta.
