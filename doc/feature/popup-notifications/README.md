# Popup visual — Documentação

Aviso visual do sistema quando chega um evento de notificação e o agente não está com aquela conversa aberta. Usa `ServiceWorkerRegistration.showNotification` quando há suporte a ações ou o construtor nativo falha; nos demais desktops usa `new Notification`.

**Estado:** correções de `fix/notification-delivery-hardening` integradas à `main` e publicadas no fork `cesar-carlos/chatwoot`, ainda não implantadas · 01/out/2026. Evidências e aceite em [validation-report.md](./validation-report.md).

| Área | Status |
|------|--------|
| Coluna “Pop-up notification” na tabela de preferências | ✅ desktop + mobile, rótulo fixo sem tradução |
| Persistência em `users.ui_settings` | ✅ por conta (`popup_notification_flags_by_account`) |
| Disparo no `notification.created` | ✅ omite só a conversa que já está aberta |
| Nova conversa com somente Pop-up marcado | ✅ o builder cria o evento mesmo sem e-mail/Push |
| Falha na exibição | ✅ aviso traduzido uma vez por sessão; não afirma que o SO exibiu o alerta |
| Permissão do navegador no primeiro checkbox ou CTA explícito | ✅ |
| Chamada de voz (`voice_call_incoming`) | ❌ sem checkbox (popup já existe no Wavoip) |
| Push com a aba fechada | ❌ continua na coluna Notificação |
| i18n | ✅ textos explicativos em en + pt_BR |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Visão / status** | Este README |
| **O que foi entregue no código** | [current-state.md](./current-state.md) |
| **Por que `ui_settings` e não uma flag de push** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **Plano as-built + arquivos** | [implementation-plan.md](./implementation-plan.md) |
| **Próximos passos** | [improvements-backlog.md](./improvements-backlog.md) |

---

## Decisões fechadas

| Tópico | Decisão |
|--------|---------|
| Canal | Action Cable inicia o aviso; desktop usa `Notification` da página, mobile usa `showNotification` do service worker |
| Evento | `notification.created` (Action Cable), depois do gate de inbox |
| Quando mostrar | Janela oculta, ou visível numa conversa diferente |
| Persistência | `users.ui_settings.popup_notification_flags_by_account`, por conta, com rollback em erro |
| Padrão | Array vazio por conta — o agente marca o que quer |
| Janela visível | Usa conta e conversa normalizadas pelo router, incluindo inbox, equipe, etiqueta, visão personalizada, menções, participantes, não atendidas e inbox de notificações |
| Corpo | Texto da mensagem, sem repetir o nome que já está no título |
| Backend | Sem migration; APIs autenticadas de teste por dispositivo e leitura individual, além de leitura em lote com limite de ID; preferências Pop-up continuam em `ui_settings` |
| Voz | Sem checkbox; CTA explícito concede a permissão usada pelo popup Wavoip |
| Clique | Desktop foca a janela; o service worker prefere cliente da mesma conta e navega para a conversa |
| Leitura | `notification.updated` com `read_at` fecha só o ID correspondente; `notifications.read` fecha apenas IDs até o limite do lote. Leitura pelo contato não fecha avisos do agente |
| Ações | “Abrir conversa” e “Marcar como lida” em avisos persistentes reais, quando a plataforma permite; sem suporte, o clique comum abre a conversa |
| i18n | Textos explicativos em **en + pt_BR**; rótulo “Pop-up notification” fixo |
| Fork | Helper em `custom/` + `// FORK:` em `actionCable.js` e `NotificationPreferences.vue` |

---

## Fluxo (resumo)

```mermaid
flowchart LR
  msg[Mensagem criada] --> builder[NotificationBuilder]
  builder --> cable["Action Cable notification.created"]
  cable --> store[Store do sino]
  cable --> popup["Pop-up notification se o tipo estiver ligado e a conversa não estiver visível"]
```

---

## Problema de produto

A tabela de preferências só tinha e-mail e push. O som fica em outra seção e não mostra o conteúdo. O pop-up cobre o caso em que o painel está aberto, conectado e outra conversa está em exibição. Com o app do celular suspenso, o JavaScript para e este aviso não dispara; para receber com o app fechado é preciso ativar o Push neste dispositivo, liberar a permissão e selecionar os tipos de evento na coluna Push.

As preferências de Pop-up e de Push são independentes. A entrega visual também depende de permissão do navegador e da apresentação pelo sistema operacional; um aviso de falha aparece se a tentativa de exibição pelo painel falhar. A validação final em iOS/Android reais continua necessária antes de declarar a experiência móvel homologada.

---

*Última atualização: 01/out/2026*

O seletor mostra **Verificando** durante a consulta do dispositivo. Preferências só podem ser alteradas após carregamento bem-sucedido da conta; erros oferecem **Tentar novamente**. O teste neste dispositivo confirma aceitação pelo provedor, nunca exibição pelo aparelho. Consulte também [PWA](../pwa/README.md).
