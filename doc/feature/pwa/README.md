# PWA e Web Push do painel

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

Revisão de 24/out/2026. Os documentos descrevem o estado do código na `main`; o histórico de candidatos e branches anteriores foi consolidado.

## Estado

| Item | Estado |
|------|--------|
| Código | Na `origin/main`, commit `f5ac1d6fd2`: correção de reinstalação, preferência por usuário, recuperação, estado de entrega e limpeza de inscrições. Inclui o merge do upstream 4.19.1 |
| Produção | Último release **documentado**: `f58ca95d4d`, de 01/out/2026. Esta revisão não conseguiu confirmar o release em execução (o domínio público respondeu 403 ao host de desenvolvimento). Ativação guiada, instalação mobile, regra de time, recuperação mobile e o merge 4.19.1 só estão em produção se houve deploy posterior. Confirmar com `bin/fork-pwa-smoke` |
| Homologação em aparelhos | **Pendente**: instalação Android/iOS e Push com app fechado |

Resposta HTTP correta e testes automatizados não comprovam instalação nem exibição de banner. A homologação exige instalar a PWA e receber uma notificação real com o aplicativo fechado.

## O que existe

| Recurso | Implementação |
|---------|---------------|
| Manifesto white-label | `/manifest.webmanifest` (canônico) e `/manifest.json` (alias), gerados por `Custom::WebAppManifestBuilder` |
| Metadados de instalação | Link do manifesto, `theme-color`, Apple Touch, favicon e `mobile-web-app-capable`/`apple-mobile-web-app-capable` presentes mesmo com `DISPLAY_MANIFEST=false` |
| Identidade | `INSTALLATION_NAME`, `BRAND_NAME`, `id: "/"` e `display: standalone` |
| Ícones | Seis URLs configuráveis no Super Admin; PNGs Se7e v2 distintos para `any` e `maskable` (192/512), Apple Touch 180 e favicon ICO em `/brand-assets/` |
| Instalação guiada | `beforeinstallprompt` no Chromium, instruções por plataforma, cartão de promoção mobile e diagnóstico de manifesto/ícones |
| Web Push | Opt-in por usuário, convite único na PWA, recuperação de quem ficou com o opt-out antigo, rotação VAPID, limpeza no logout sem gravar recusa e revalidação ao voltar ao app |
| Teste neste dispositivo | Envia ao próprio endpoint, no máximo três a cada 60 segundos, com confirmação **Recebi / Não recebi** |
| Clique e ações | Reutiliza uma janela do painel da mesma origem; **Abrir conversa** e **Marcar como lida** em plataformas com suporte |
| Pop-up | Canal separado: depende do painel aberto e da conexão em tempo real |
| Verificação do release | `bin/fork-pwa-verify` chama `bin/fork-pwa-smoke` com o SHA de `HEAD` e os seis ícones v2 |

## Requisitos do aparelho

- **Android:** Chrome atual, HTTPS e manifesto/ícones acessíveis na mesma origem.
- **iPhone/iPad:** iOS/iPadOS 16.4 ou superior; abrir no Safari, adicionar à Tela de Início e iniciar pelo ícone. Push só é habilitado na PWA instalada.
- **Push:** chaves VAPID válidas, permissão concedida por clique do usuário e inscrição ativa naquele navegador/PWA. Aba do navegador e PWA instalada têm permissões e inscrições separadas.

## Limites que o aplicativo não controla

- O sucesso do diagnóstico significa que o serviço Push **aceitou** a mensagem. A exibição depende do sistema, das permissões e da política de energia.
- Android pode tocar som ou acender a tela e ocultar o banner flutuante, conforme a categoria do canal. No iOS, Banners, Foco e Resumo Agendado alteram a apresentação.
- A ausência de `beforeinstallprompt` não prova instalação nem incompatibilidade.
- O aviso `Banner not shown: beforeinstallpromptevent.preventDefault() called` é esperado: o convite fica no botão **Instalar**, que chama `prompt()` após o clique.
- Erros 404 em `/rails/active_storage/disk/` são falhas de entrega de uploads, não problemas de instalação da PWA.

## Documentos

- [Estado atual e arquitetura](./current-state.md)
- [Mapa do código, validação e publicação](./implementation-plan.md)
- [Decisões técnicas](./implementation-decision-tree.md)
- [Pendências e melhorias](./improvements-backlog.md)
- Evidências detalhadas e histórico de validação: [Pop-up notifications — relatório de validação](../popup-notifications/validation-report.md)
