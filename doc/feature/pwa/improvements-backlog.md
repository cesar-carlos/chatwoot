# PWA — pendências e melhorias

## Pendências operacionais e de validação

Todo o código está na `main` e em `origin/main`. O que falta é confirmar a publicação e homologar em aparelhos.

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Confirmar o release em execução | `bin/fork-pwa-smoke` passa com o SHA esperado. Último release documentado: `f58ca95d4d` (01/out/2026), anterior à ativação guiada, à instalação mobile, à regra de time, à recuperação mobile e ao merge do upstream 4.19.1 |
| P0 | Publicar a correção de reinstalação, com autorização | Branch `fix/pwa-push-reinstall`. Build de SDK/Rails/dashboard, release isolado, storage compartilhado, backup e migration aditiva (`last_synced_at`, `last_push_at`, `last_push_status`, `last_push_error`), restart web/workers, invalidação de `/sw.js` e `/notification-worker.js`, `bin/fork-pwa-verify` |
| P0 | Validar Android e iOS | Instalação standalone, mensagem real e Push com app fechado; clique abre a conversa certa; ações funcionam |
| P0 | Validar retomada | App suspenso reconecta o Action Cable e sincroniza ao voltar |
| P0 | Homologar a reinstalação | Logout não grava mais opt-out, a preferência é por usuário e quem ficou com o `false` antigo recebe um convite único. Falta confirmar em aparelhos os cenários da homologação manual, inclusive o convite de recuperação uma única vez |
| P1 | Reproduzir o relato do iPhone sem banner | Conferir inscrição e preferências **dentro da PWA instalada** (aba e PWA têm inscrições separadas), tela bloqueada, Banners/Foco/Resumo Agendado. Não declarar a causa sem reprodução |
| P1 | Acessibilidade | Teclado, foco e leitor de tela em convite, cartão de instalação e diagnóstico; telas pequenas |
| P1 | Orientar reinstalação de atalhos antigos | Clientes com manifesto ou ícone antigos removem o atalho e instalam de novo |
| P1 | Monitorar entrega | Jobs, `result=accepted/failed/discarded`, inscrições expiradas e diagnósticos sem regressão |

## Melhorias pequenas

- Branches locais do fork já integradas (`feat/guided-push-permission`, `feat/mobile-pwa-install-diagnostics`, `feat/team-unassigned-notifications` e outras) podem ser removidas depois de confirmar que `main` as contém; a remoção exige autorização.

## Descartado

- Localizar o aviso genérico do worker pelo idioma do perfil. O worker não tem acesso ao perfil, e persistir o idioma aumenta a complexidade de um texto que quase nunca aparece. Continua `navigator.language` (português se começa com `pt`, inglês nos demais).

## Fora do escopo

- Experiência offline: exige projeto próprio de cache, autenticação e atualização.
- Métrica de conversão do botão de instalação, se houver necessidade de produto.
- Diagnóstico de permissões por fabricante Android, se surgirem incidentes reproduzíveis.

Não adicionar polling em segundo plano, Firebase para a PWA ou tentativa de manter o WebSocket vivo durante a suspensão: não substituem o Web Push e aumentam consumo de bateria e complexidade. Também não planejar flags JS de prioridade como garantia de banner: categorias Android, Banners e Foco do iOS pertencem ao sistema.
