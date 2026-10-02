# Popup visual — Estado atual

## Regra de time sem agente — candidato de 02/out/2026

Implementação de `fix/team-notification-hardening` (`5dc0fb450b`), incluindo `feat/team-unassigned-notifications` (`f3e91283ff`), incorporada por fast-forward à main local em 02/out/2026. O worktree de integração foi criado de `origin/main` atualizado e preservou a main anterior `b4334fdc0f`. Não houve publicação, build ou deploy; produção permanece inalterada. [Auditoria da integração](./validation-report.md#integração-das-notificações-por-time--02out2026).

- Identificador: `team_conversation_assignment`, enum aditivo `10`; flags `email_team_conversation_assignment`, `push_team_conversation_assignment` e `popup_team_conversation_assignment`. Nenhuma migration: e-mail/Push usam as colunas de bits existentes, Pop-up continua em `ui_settings` por conta. Nenhuma seleção automática ou alteração retroativa.
- Disparo: `team.changed`; também `assignee.changed` quando uma atribuição de agente/bot é removida, mantendo o time. Se ambos mudarem juntos, somente `team.changed` cria o aviso. Uma conversa criada já no time também usa o callback de atribuição existente. Atualizações comuns e novas mensagens não repetem esse evento.
- Elegibilidade: conversa **aberta**, time presente, sem agente individual, bot legado ou assignee de IA; membro do time na mesma conta ativa, vínculo com a conta, acesso às notificações e `ConversationPolicy#show?`. Contato bloqueado continua excluído pelo builder. Administradores/inbox members fora do time não são destinatários.
- Preferência: precisa selecionar ao menos um canal. Pop-up sozinho cria a notificação, sem enfileirar Push/e-mail. Falta de preferência significa desativado. Push continua exigindo inscrição e permissão no dispositivo; Pop-up exige painel conectado e omite a conversa já visível.
- Segurança de entrega: `meta.assignment_team_id`, `assignment_team_name` e `assignment_revision` registram o contexto original. O nome é capturado na gravação da atribuição, não consultado novamente quando o job atrasado cria a notificação. Push e e-mail revalidam vínculo, políticas, time, revisão, ausência de agente e preferência no processamento; o mailer revalida também na renderização. Mudança de time, saída do membro, atribuição de agente/bot ou fechamento da conversa invalida a entrega pendente.
- Idempotência: cada mudança de time/agente/bot recebe uma revisão opaca. O evento leva essa revisão em `changed_attributes.additional_attributes`; um evento antigo não vale novamente após time A → B → A ou nova retirada de agente. Criação e registro do destinatário usam a mesma transação, com bloqueio da linha da conversa. Jobs concorrentes ou repetidos não recriam o aviso, inclusive se a limpeza do histórico já o apagou. Falha parcial permite retomar os demais membros sem repetir os anteriores; falha na transação não registra recebimento.
- Persistência: `additional_attributes.team_notification_transition` guarda somente a revisão atual, nome original e IDs dos destinatários cuja notificação foi criada. Não guarda tokens, conteúdo de mensagem ou histórico ilimitado; reinicia na próxima atribuição. Atualizações normais preservam o estado sob bloqueio, ignorando valores enviados pelo cliente. O campo interno não aparece nos payloads de conversa/webhook nem no metadata da API de mensagens. Não há migration ou Redis adicional para deduplicação.
- Histórico e autorização: `AccessibleScope` filtra em SQL antes da paginação e dos contadores, alinhado a `ConversationPolicy#show?`, incluindo papéis customizados. Sino, unread count, leitura em lote e operações individuais usam o escopo; eventos de criação/atualização só enviam conteúdo a destinatários ainda autorizados. Uma conversa que deixa de ser elegível para **nova entrega** não perde o histórico se o usuário continua autorizado a vê-la. Não são apagadas notificações apenas por perda de acesso.
- Conteúdo: título com conversa e time; corpo Push/Pop-up com resumo da última mensagem recebida (ou enviada, se não houver recebida). Pop-up recebe `notification_title` opcional para explicar o evento e conserva o nome do contato no corpo; payloads anteriores mantêm o comportamento. Título Push/Pop-up segue o idioma válido do usuário, com fallback para o da conta. E-mail segue o locale da conta, contém link à conversa e rodapé de preferências; lista do sino tem rótulo e ícone de time em en/pt_BR.

As preferências mostram uma explicação compartilhada em desktop e nos três canais mobile: avisa na atribuição/retirada de agente, não a cada nova mensagem. Textos somente em en/pt_BR.

Não há aviso retroativo de conversas já aguardando, gatilho por simples reabertura, polling ou tentativa de manter o WebSocket em segundo plano. Eventos antigos sem identidade de transição não geram este novo aviso; notificações antigas sem nome/revisão preservam fallback compatível, sem inventar o contexto passado. Avisos já entregues e dados anteriormente carregados no navegador não são revogados automaticamente; a consulta seguinte e novos eventos respeitam o acesso atual. Não há garantia de entrega exatamente uma vez pelo provedor: a proteção é para a criação/fanout desta regra. Limitações de apresentação do sistema permanecem. [Evidências e aceite manual](./validation-report.md#revisão-de-segurança-e-idempotência--02out2026).

## Estado após integração local — 02/out/2026

Os candidatos abaixo estão incorporados à `main` local, incluindo `063ee874a1`. Não há mudança de canais ou regras de Pop-up durante a integração. Menções a candidatos não publicados são histórico; GitHub, build/deploy e homologação em aparelhos ainda não foram concluídos. [Validação](./validation-report.md#integração-na-main-local--02out2026).

## Revisão do diagnóstico assistido

Candidato mais recente: `fix/pwa-assisted-diagnostics-review`, ainda local. Fechamento do diálogo invalida resultados pendentes; respostas tardias não reabrem a interface, inclusive durante nova investigação. Um envio já iniciado pode ser entregue mesmo após fechar.

Verificação/ativação/teste/desativação têm progresso compartilhado e correto. Contexto inseguro, falta de APIs e configuração VAPID ausente são motivos distintos, não permissão bloqueada. O aviso de nenhum evento Push selecionado só aparece para inscrição confirmada e preferências da conta carregadas com sucesso, fora de gravação; oferece link, sem alterar flags.

Sem mudanças nos eventos, autorização, fechamento de avisos, API, payload ou preferências de Pop-up. Consulta de instalação cancelável e evidências: [PWA](../pwa/current-state.md) e [relatório](./validation-report.md#revisão-do-candidato--02out2026).

## Diagnóstico assistido no candidato mobile

Em `feat/mobile-pwa-install-diagnostics`, o botão do próprio dispositivo passa por uma verificação fresca antes do envio. Endpoint anteriormente exibido não é tomado como inscrição atual. Permissão negada/default, opt-out, iOS fora da PWA e falta de suporte impedem o teste e oferecem ajuda adequada, sem prompt automático.

`usePushDevice` serializa consulta, recuperação, ativação e teste entre superfícies e invalida operações por sessão/desmontagem. `PushDeviceDiagnostics` pergunta sobre exibição somente com `accepted: true`; **Não recebi** verifica novamente e não reenvia. 404/429/401/403/422/502/rede/timeout permanecem distintos de permissão bloqueada.

A API e o limite de três testes/minuto são os existentes. Nenhuma alteração no protocolo, payload real, eventos Pop-up, flags por conta ou preferências foi feita. O candidato anterior está incorporado; ambos continuam fora de produção. Detalhes: [PWA](../pwa/current-state.md).

## Autorização guiada no candidato de 02/out/2026

O novo fluxo de permissão está isolado em `feat/guided-push-permission`. Ele reutiliza a Notifications API, mas mantém a inscrição Web Push separada dos avisos iniciados pelo painel. Os eventos e a persistência de Pop-up permanecem inalterados.

As preferências recebem estado de permissão atualizado após ativação ou retorno ao aplicativo. O convite não marca eventos, não muda opt-out e não tenta solicitar novamente uma permissão negada. Detalhes: [arquitetura PWA](../pwa/current-state.md).

Inventário das correções de `fix/notification-delivery-hardening`, integradas à `main`, publicadas no fork e implantadas no release `f58ca95d4d` em 01/out/2026. Web e worker estão na mesma versão; o smoke público passou. A homologação da apresentação dos avisos em aparelhos continua pendente.

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Coluna desktop | Grid 6 / 2 / 2 / 2: tipo, e-mail, notificação do sistema, “Pop-up notification”; títulos quebram linha sem sobreposição e linhas crescem com o texto |
| Lista mobile | Terceira seção “Pop-up notification”, sem a linha de chamada de voz; rótulos clicáveis |
| Persistência | `ui_settings.popup_notification_flags_by_account[accountId]`, via action estrita com rollback; controles ficam bloqueados durante o salvamento para impedir gravações concorrentes |
| Lista antiga | `popup_notification_flags` (flat) só é lida se o mapa por conta ainda não existe |
| Corpo | Texto da mensagem; o prefixo `"Nome: "` sai quando o título já é o contato |
| Janela em foco | Compara parâmetros normalizados do router; cobre todas as rotas de conversa e não confunde o ID de uma visão personalizada com uma conversa |
| Leitura individual | `notification.updated` com `read_at` fecha somente `account_id + notification_id`, inclusive criação pendente |
| Leitura em lote | `notifications.read` é enviado somente ao destinatário, com `user_id`, conta, conversa opcional e `through_notification_id`; banco, store e fechamento respeitam o mesmo limite |
| Leitura pelo contato | `conversation.read` não fecha a notificação do agente |
| Chamada de voz | Célula com “—”; CTA explícito concede a permissão usada pelo Wavoip |
| Permissão | Primeiro checkbox ou CTA pede `Notification.requestPermission()` |
| Permissão negada | Checkbox não grava; `useAlert` com `POPUP_PERMISSION_ERROR` |
| Disparo | `onNotificationCreated` chama `showPopupNotification` depois de `addNotification` |
| Gate | Mesmo `canAccessInboxView` do sino, calculado para a conta do evento |
| Nova conversa | O overlay do `NotificationBuilder` cria `conversation_creation` quando apenas o Pop-up dessa conta está marcado |
| Título | `primary_actor.meta.sender.name`, senão o `notification_type` |
| Ícone | Thumbnail do contato ou `/brand-assets/logo_thumbnail.svg` |
| Agrupamento | `tag` `<notification_type>_<display_id>_<notification_id>` corresponde ao Push do mesmo evento |
| Mobile com painel vivo | Se `new Notification` falhar, `showNotification` do service worker tenta mostrar o aviso; falhas geram alerta traduzido uma vez por sessão |
| Clique | Desktop foca a janela; service worker prefere janela da mesma conta, reutiliza cliente adequado ou abre nova janela |
| Falha no clique | Cliente desaparecido, navegação rejeitada ou foco rejeitado levam à abertura de nova janela na mesma origem |
| Preferências | Bloqueadas até o carregamento bem-sucedido, com erro/retry, proteção de troca de conta e rollback |
| Diagnóstico do dispositivo | CTA só aparece com endpoint confirmado; limite de três testes por minuto por usuário |
| Ações | Quando a plataforma oferece ações, Pop-up usa aviso persistente também no desktop. Backend idempotente e autorizado; o worker não faz chamadas autenticadas nem guarda credenciais |
| Tipos | Os mesmos da tabela, exceto `voice_call_incoming` |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Popup da conversa que já está aberta | Conta e `display_id` da URL são os mesmos; o agente está vendo a mensagem |
| Popup com PWA/aba suspensa no celular | O OS congela o JavaScript e o websocket cai |
| Aviso com o app fechado | Continua sendo Web Push (inscrição neste dispositivo + coluna Push + VAPID) |
| Checkbox de chamada de voz | `notifyIncomingWavoipOffer` usa a permissão concedida pelo CTA genérico |
| Nova coluna no banco | Preferência é dado de UI, não canal de entrega do servidor |
| Toast dentro da página | Só o aviso nativo do sistema operacional; em primeiro plano, o SO decide como apresentá-lo |
| Garantia de exibição pelo aparelho | A API confirma a tentativa; o sistema operacional controla a apresentação. É necessário validar em aparelhos reais |
| Resposta e silenciamento | Fora do escopo; as únicas ações são abrir e marcar como lida |
| Intenção expirada | O nonce do clique é consumido uma vez, dura até 60 segundos e não sobrevive ao reinício do worker. Se expirar, a UI orienta a operação manual, sem escrever automaticamente |

Validação e critérios ainda pendentes em [validation-report.md](./validation-report.md).

---

## Relação com os outros avisos

| Canal | Onde configura | Quando chega |
|-------|----------------|--------------|
| Som | Alertas de áudio (`enable_audio_alerts`) | `message.created`, página viva |
| Push | Coluna Notificação | Service worker, aba pode estar fechada |
| E-mail | Coluna E-mail | Job no servidor |
| Popup | Coluna “Pop-up notification” | Página viva e conectada, exceto na conversa que já está aberta |
