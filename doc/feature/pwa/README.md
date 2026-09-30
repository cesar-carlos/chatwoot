# PWA do painel

O painel oferece instalação como aplicativo web e notificações Web Push. A instalação depende do manifesto entregue ao navegador; as notificações dependem também da permissão e de uma inscrição Push ativa.

**Estado do código:** branch `fix/pwa-mobile-push`, 30/set/2026. **Estado da produção consultada:** ainda usa o manifesto antigo; veja [estado atual](./current-state.md).

| Recurso | Implementação no branch |
|---------|-------------------------|
| Manifesto white-label | `/manifest.webmanifest`, com `/manifest.json` como alias |
| Link no HTML | Sempre presente, inclusive com `DISPLAY_MANIFEST=false` |
| Instalação no Chrome | Ícones PNG de 192×192 e 512×512, `display: standalone` |
| Nome e ícones | `INSTALLATION_NAME`, `BRAND_NAME`, `PWA_ICON_192_URL` e `PWA_ICON_URL` |
| Service worker | `/sw.js`, para Push e clique na notificação; sem cache offline |
| iOS | Instruções para abrir no Safari e adicionar à Tela de Início |

## Documentos

- [Estado do código e da produção](./current-state.md)
- [Implementação e publicação](./implementation-plan.md)
- [Decisões técnicas](./implementation-decision-tree.md)
- [Melhorias posteriores](./improvements-backlog.md)

## Instalação e notificações

O Chrome precisa encontrar o link do manifesto no HTML e carregar os dois ícones declarados. Ter o arquivo `/manifest.json` acessível, isoladamente, não torna a página instalável. No iOS/iPadOS, o usuário abre o site no Safari, usa **Adicionar à Tela de Início** e inicia o app pelo ícone.

Push é uma notificação do sistema e pode chegar com o painel suspenso ou fechado. O alerta **Pop-up** depende da página aberta e da conexão em tempo real. O WebSocket pode ser suspenso pelo celular sem impedir a entrega de Push.

O resultado de instalação no aparelho e a entrega de Push devem ser conferidos após o deploy; testes de código não substituem essa validação.
