# Popup visual — Plano de implementação (as-built)

## Incremento: time sem agente — candidato de 02/out/2026

Revisão final de `fix/team-notification-hardening`, incluindo o candidato anterior e incorporada à main local por fast-forward em 02/out/2026:

- `custom/app/services/custom/notification/team_assignment_transition.rb` e callback Custom da conversa: revisão por atribuição, snapshot do nome e ledger limitado à transição atual; bloqueio PostgreSQL e persistência atômica com a notificação. Não usa TTL de Redis nem migração para deduplicação.
- `team_assignment_eligibility.rb`: revalida também a revisão antes de Push/e-mail; listener exige a identidade do evento para impedir reinterpretação de eventos atrasados.
- `accessible_scope.rb` e finder/controller/listener Custom: autorização em SQL para lista/contadores, leitura em lote, operações individuais e conteúdo dos eventos de notificação. Matriz de papéis comparada com `ConversationPolicy` em regressões.
- Modelo/presenter Custom e um hook `FORK:` na API de mensagens: mantêm o ledger fora dos payloads públicos e impedem sobrescrita por atualizações comuns de atributos.
- `NotificationEventDescription.vue`, `<script setup>`/Tailwind: explicação reutilizada nos canais desktop/mobile, sem converter o componente legado; somente en/pt_BR.
- Regressões: dois workers reais com conexões PostgreSQL distintas, rollback, retry parcial, histórico apagado, A → B → A, renomeação antes do job, revogação de acesso, contadores e os quatro locais da explicação na interface.

Não ampliar o gatilho para reabertura de conversa neste incremento. Aceite em aparelhos permanece separado da validação automatizada.

- `custom/app/listeners/custom/notification_listener.rb`: usa os eventos de atribuição existentes; não altera Action Cable nem adiciona scheduler.
- `custom/app/services/custom/notification/team_assignment_eligibility.rb`, `notification_builder.rb` e `delivery_access.rb`: concentram elegibilidade, opt-in por canal e revalidação do time original.
- `custom/app/models/custom/notification.rb`: captura `assignment_team_id`, título localizado e corpo; enum aditivo e flags derivadas no OSS.
- `custom/app/services/custom/notification/email_notification_service.rb`, mailer/template Custom: habilitam o novo canal e revalidam o envio assíncrono.
- `custom/app/javascript/dashboard/helper/teamNotificationPreferences.js`: insere a linha após a atribuição individual e fornece ícone do sino. `usePopupNotifications` aceita o título opcional sem alterar payloads anteriores.
- Hooks upstream mínimos `FORK:`: enum, listener, serviço de e-mail, composição das preferências e ícone. Textos somente en/pt_BR. Specs correspondentes em `spec/custom`; regressão de Pop-up existente ampliada.

Entrega atual incorporada à main local, sem publicação/build/deploy. Será necessário build frontend e atualização coordenada de todas as instâncias web/workers após autorização; callbacks e consumidores de eventos devem usar a mesma versão. Não há migration, nova configuração nem alteração de chaves VAPID. [Semântica](./current-state.md#regra-de-time-sem-agente--candidato-de-02out2026), [validação](./validation-report.md#revisão-de-segurança-e-idempotência--02out2026) e [integração](./validation-report.md#integração-das-notificações-por-time--02out2026).

## Integração local concluída — 02/out/2026

Todos os candidatos abaixo, até `063ee874a1`, incorporados à `main` local por fast-forward, sem conflitos. A validação foi repetida em worktree isolado; nenhuma outra branch do fork ficou pendente. GitHub, novo build, deploy e homologação real ainda são etapas separadas. [Evidências](./validation-report.md#integração-na-main-local--02out2026).

## Revisão do candidato assistido

Implementado em `fix/pwa-assisted-diagnostics-review`: invalidar apresentação ao fechar diagnóstico, ignorar respostas tardias, exibir atividade correta, explicar motivos específicos de ambiente indisponível e orientar seleção de eventos quando a inscrição não tem eventos Push na conta. Não alterados os contratos de leitura, autorização, entrega e Pop-up.

Regressões incluem teste pendente após fechamento/desmontagem, operação compartilhada, motivos sem envio, aviso após carga bem-sucedida e integração com troca de conta/salvamento. Consulta de instalação ganha cancelamento/timeout e retry explícito no mesmo candidato. [Evidências](./validation-report.md#revisão-do-candidato--02out2026).

Entrega local, sem main/GitHub/build/deploy. Homologação em aparelhos e acessibilidade continuam necessárias; o servidor não comprova exibição pelo sistema operacional.

## Incremento de diagnóstico e instalação

Implementado no candidato `feat/mobile-pwa-install-diagnostics`, incluindo `feat/guided-push-permission`. Sem merge, GitHub, build ou deploy.

Fluxo: clique → ambiente/permissão/opt-out atuais → ativação do worker e sync pelo helper existente → endpoint confirmado → teste. Obstáculos verificáveis abrem ajuda no mesmo diálogo, sem enviar. Solicitação nativa permanece exclusivamente no CTA **Permitir notificações**. Aceitação exige campo booleano verdadeiro; confirmação visual vem somente do usuário.

**Não recebi** reexecuta conferências, sem envio automático. 404 oferece sync explícito; teste posterior exige outro clique. 429 pede aguardar; 401/403 orientam sessão/acesso; falhas de cadastro/provedor/transporte são classificadas sem prometer desbloqueio do sistema.

As regressões e a matriz de homologação estão no [relatório](./validation-report.md#instalação-mobile-e-teste-assistido--02out2026). Não há alteração Ruby ou dos contratos Pop-up/Web Push. Instalação e dispensa local: [plano PWA](../pwa/implementation-plan.md).

## Incremento de autorização — candidato separado

Convite inicial da PWA, ajuda de desbloqueio e CTAs das preferências foram implementados em `feat/guided-push-permission`, sem publicação/deploy. Reutilizam a lógica Web Push existente; não substituem o composable de Pop-up.

As regressões cobrem especificamente que default → granted pela autorização de Pop-up **não** gera inscrição automática, enquanto a recuperação de permissão bloqueada no fluxo Push respeita opt-out. Ver [plano PWA](../pwa/implementation-plan.md) e [evidências](./validation-report.md#ativação-guiada--candidato-de-02out2026).

Documento **as-built das correções** de `fix/notification-delivery-hardening`, integradas à `main`, publicadas no fork e implantadas no release `f58ca95d4d` em 01/out/2026. Build/smoke concluídos; homologação em aparelhos pendente. Decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Dar ao agente uma coluna **Pop-up notification** na tabela de preferências e mostrar o aviso nativo do navegador com o contato e o texto da mensagem, exceto quando essa conversa já está aberta na janela.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Helper `usePopupNotifications` | ✅ |
| 2 | Gancho em `onNotificationCreated` | ✅ |
| 3 | Coluna desktop responsiva e seção mobile com rótulos clicáveis | ✅ |
| 4 | Textos explicativos em en + pt_BR; rótulo fixo “Pop-up notification” | ✅ |
| 5 | Docs em `doc/feature/popup-notifications/` | ✅ |
| 6 | Fallback via service worker quando o construtor `Notification` falha no mobile | ✅ |
| 7 | Criação de `conversation_creation` com preferência somente Pop-up | ✅ |
| 8 | Fechamento de múltiplos avisos, bloqueio de salvamentos concorrentes e feedback de falha | ✅ |

---

## Detalhe técnico

### 1. Persistência

```js
// users.ui_settings
popup_notification_flags_by_account: {
  "1": ["popup_assigned_conversation_new_message"]
}
```

- A chave da conta é o `account_id` em string
- `withPopupFlagsForAccount` grava só a conta ativa e apaga a lista antiga `popup_notification_flags`
- Leitura: mapa da conta; se o mapa não existe, cai na lista antiga
- A gravação usa uma action Vuex que propaga falhas; em erro, a seleção anterior é restaurada e a interface informa a falha
- Os checkboxes de cada grupo ficam bloqueados enquanto a respectiva gravação está pendente

### 2. Quando o aviso abre

`showPopupNotification` sai cedo se:

- o tipo não está na lista da **conta da notificação**, ou é `voice_call_incoming`
- `Notification` não existe ou a permissão não é `granted`
- a página está visível e os parâmetros normalizados do router indicam a mesma conta e conversa, em qualquer rota suportada

O corpo passa por `popupMessageBody`: se começa com `"Nome: "`, esse prefixo sai.

Título, corpo e ícone vêm do payload do cabo:

- `notification.primary_actor.meta.sender.name` / `.thumbnail`
- `notification.push_message_body`
- `primary_actor.id` é o `display_id` da conversa

### 3. Exibição e clique

No desktop sem ações, `new Notification` cria o aviso. Quando a plataforma oferece ações ou esse construtor falha, como ocorre na maioria dos navegadores móveis, a página registra ou reutiliza `/sw.js`, aguarda sua ativação e chama `registration.showNotification`. Isso não cria uma inscrição Web Push.

No desktop, o clique faz `window.focus()`, fecha o aviso e chama `router.push` para a conversa. O router é importado só no clique. No aviso do service worker, o handler `notificationclick` fecha o aviso, prefere uma janela do painel da mesma conta e navega até a conversa; se houver apenas uma janela do painel, pode reutilizá-la mesmo em outra conta, ou abre nova janela quando não houver cliente adequado. A tag corresponde à do Web Push do mesmo evento: `<notification_type>_<display_id>_<notification_id>`.

O cliente acompanha avisos por conta e ID da notificação. `notification.updated` com `read_at` fecha só aquele ID. `notifications.read` fecha os IDs até `through_notification_id`, filtrando destinatário e conversa quando informados. `conversation.read` representa leitura pelo contato e não participa do fechamento. Placeholders da página e mensagens ao worker garantem o fechamento após uma criação pendente, sem apagar avisos posteriores. Falhas assíncronas de exibição são sanitizadas e geram feedback traduzido.

### 4. Permissão na UI

Ao marcar um checkbox, se a permissão ainda é `default`, pede `Notification.requestPermission()`. Se o resultado não for `granted`, o flag não entra no array e o alerta `POPUP_PERMISSION_ERROR` aparece. Uma ação explícita separada também concede a permissão usada pelos alertas de chamada de voz. Desmarcar não mexe na permissão nem na subscription de push.

A permissão comum de notificações não ativa Web Push. A inscrição Push tem opt-in próprio por dispositivo: só é criada pelo seletor Push e não é recriada depois de o usuário desativá-la.

---

## Arquivos

| Arquivo | Papel |
|---------|--------|
| `custom/app/javascript/dashboard/composables/usePopupNotifications.js` | Filtro, `new Notification`, fallback `showNotification`, navegação |
| `custom/app/builders/custom/notification_builder.rb` | Permite criar evento `conversation_creation` para a preferência Pop-up da conta |
| `app/javascript/dashboard/helper/actionCable.js` | `// FORK:` chama o helper depois do gate de inbox |
| `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue` | Coluna, seção mobile, gravação em `ui_settings` |
| `app/javascript/dashboard/store/modules/auth.js` | Action estrita para persistir preferências com rollback na UI |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | Textos explicativos e erros |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Mesmas chaves |
| `public/sw.js` | Entrada mínima com `importScripts('/notification-worker.js')` |
| `custom/app/javascript/dashboard/helper/notificationWorker.js` | Payload, ações, intenção descartável, clique com fallback e criação pendente |
| `custom/app/javascript/dashboard/helper/notificationActions.js` | Aguarda sessão, consome intenção, verifica destinatário e chama leitura individual |
| `custom/app/javascript/dashboard/store/notificationReadActions.js` | Aplica leitura confirmada com limite de ID, sem marcação ampla otimista |
| `custom/app/services/custom/notification/bulk_read_service.rb` | Limite comum para atualização SQL e evento direcionado ao usuário |

O Pop-up depende de `notification.created` via Action Cable e não da inscrição Web Push. Para `conversation_creation`, o builder consulta a preferência Pop-up além das flags de e-mail/Push ao decidir criar o evento. No mobile, o service worker apenas exibe e trata o clique do aviso iniciado pela página; com a PWA suspensa ou fechada, o recebimento depende do Web Push separado.

---

## Como testar

1. Perfil → Preferências de notificação → marcar Pop-up notification em “Uma nova mensagem foi criada e atribuída”.
2. Aceitar a permissão do navegador.
3. No desktop, deixar a aba do painel em segundo plano.
4. Receber uma mensagem numa conversa atribuída a esse agente.
5. O aviso do sistema mostra o nome do contato e o texto. O clique abre a conversa da conta correta.
6. Simular erro ao salvar as preferências e confirmar que a seleção anterior é restaurada.
7. Na PWA móvel instalada, manter o painel aberto em outra conversa e confirmar que o aviso é exibido via service worker e abre a conversa correta.
8. Marcar somente Pop-up para nova conversa, deixar e-mail e Push desmarcados e confirmar a criação do aviso.
9. Gerar dois avisos para a mesma conversa e marcar um ID como lido; só aquele deve fechar. Na leitura em lote, fechar apenas IDs até o limite informado. Inserir uma notificação durante a leitura e confirmar que permanece não lida. Repetir com criação móvel pendente e em múltiplas abas.
10. Simular falha do service worker e confirmar um alerta de falha, sem repetição por mensagem; testar múltiplas janelas em contas distintas e verificar a preferência pela conta de destino.

Com o painel visível, esperar o Pop-up quando outra conversa estiver aberta, mas não quando a mesma conversa da mesma conta já estiver em exibição. Não esperar Pop-up com a PWA suspensa; esse cenário é atendido exclusivamente por Web Push. A apresentação do aviso em primeiro plano depende do sistema operacional.

## APIs e ações

`POST /api/v1/notification_subscriptions/test` aceita o endpoint browser do próprio usuário, usa texto de diagnóstico definido pelo servidor e não cria `Notification`. Retorna `422` para entrada inválida, `404` para inscrição indisponível, `429` para limite excedido e `502` para entrega não aceita. O limite é de três tentativas por usuário em cada janela de minuto do servidor, com Redis.

`POST /api/v1/accounts/:account_id/notification_actions/:notification_id/read` busca somente notificações do usuário/conta e revalida `NotificationPolicy#access?` e `ConversationPolicy#show?`. A leitura é idempotente. O worker encaminha uma intenção sem credenciais; o frontend aguarda a sessão e valida o destinatário. Sem sessão, exige login e descarta a operação automática. “Marcar como lida” abre `/app/accounts/:id/inbox-view`, não a conversa, para não atualizar last-seen e ler outros avisos acidentalmente.

Evidências automatizadas, limites e checklist de aparelhos: [validation-report.md](./validation-report.md).
