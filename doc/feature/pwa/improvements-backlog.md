# PWA — pendências e melhorias

## Pendências operacionais e de validação

Todo o código está na `main` e em `origin/main`. O que falta é confirmar a publicação e homologar em aparelhos.

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Confirmar o release em execução | `bin/fork-pwa-smoke` passa com o SHA esperado. Último release documentado: `f58ca95d4d` (01/out/2026), anterior à ativação guiada, à instalação mobile, à regra de time, à recuperação mobile e ao merge do upstream 4.19.1 |
| P0 | Publicar a `main` atual, com autorização | Build de SDK/Rails/dashboard, release isolado, storage compartilhado, restart web/workers, invalidação de `/sw.js` e `/notification-worker.js`, smoke público com a nova verificação do worker. Sem migration prevista |
| P0 | Validar Android e iOS | Instalação standalone, mensagem real e Push com app fechado; clique abre a conversa certa; ações funcionam |
| P0 | Validar retomada | App suspenso reconecta o Action Cable e sincroniza ao voltar |
| P0 | Homologar a reinstalação | Corrigido o logout que gravava opt-out (ver [plano](./implementation-plan.md#resultado-da-revisão-de-24out2026)); falta confirmar em aparelhos os cenários de reinstalação listados na homologação manual. **Usuários que já saíram uma vez com a versão anterior ficam com `chatwoot_push_enabled=false` salvo**: o valor não distingue logout de recusa, então mesmo após o deploy precisam ativar o dispositivo uma vez em Preferências → Notificações |
| P1 | Reproduzir o relato do iPhone sem banner | Conferir inscrição e preferências **dentro da PWA instalada** (aba e PWA têm inscrições separadas), tela bloqueada, Banners/Foco/Resumo Agendado. Não declarar a causa sem reprodução |
| P1 | Acessibilidade | Teclado, foco e leitor de tela em convite, cartão de instalação e diagnóstico; telas pequenas |
| P1 | Orientar reinstalação de atalhos antigos | Clientes com manifesto ou ícone antigos removem o atalho e instalam de novo |
| P1 | Monitorar entrega | Jobs, `result=accepted/failed/discarded`, inscrições expiradas e diagnósticos sem regressão |

## Melhorias pequenas

- O aviso genérico do worker segue `navigator.language` do navegador (pt ou en), não o idioma escolhido no perfil do painel. Só aparece com payload inválido ou falha de apresentação; usar o idioma do perfil exigiria enviá-lo ao worker.
- O limite de três testes por minuto usa janela fixa; na virada do minuto um usuário pode enviar até seis. Aceitável para um diagnóstico; revisar se houver abuso.
- Branches locais do fork já integradas (`feat/guided-push-permission`, `feat/mobile-pwa-install-diagnostics`, `feat/team-unassigned-notifications` e outras) podem ser removidas depois de confirmar que `main` as contém; a remoção exige autorização.

## Fora do escopo

- Experiência offline: exige projeto próprio de cache, autenticação e atualização.
- Métrica de conversão do botão de instalação, se houver necessidade de produto.
- Diagnóstico de permissões por fabricante Android, se surgirem incidentes reproduzíveis.

Não adicionar polling em segundo plano, Firebase para a PWA ou tentativa de manter o WebSocket vivo durante a suspensão: não substituem o Web Push e aumentam consumo de bateria e complexidade. Também não planejar flags JS de prioridade como garantia de banner: categorias Android, Banners e Foco do iOS pertencem ao sistema.
