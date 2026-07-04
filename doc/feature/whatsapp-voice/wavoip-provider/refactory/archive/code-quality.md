# Qualidade de código — Wavoip (arquivado)

> Conteúdo integral preservado para consulta histórica. Ver [../CHANGELOG.md](../CHANGELOG.md)
> para o resumo condensado. O texto original completo (código antes/depois de cada item) está
> disponível no histórico do git para este arquivo antes de 04 jul. 2026.

Duplicações de lógica, estado global problemático e problemas de performance identificados
na revisão de 26 jun. 2026. Todos os 14 itens abaixo foram corrigidos.

- **QC-01** · `mark_webhook_verified!` duplicado em dois serviços — consolidado em
  `Channel::Wavoip#mark_webhook_verified!` com `with_lock`.
- **QC-02** · `update_conversation` duplicado em dois serviços — extraído para
  `Call#sync_conversation_call_attributes!`.
- **QC-03** · `call.reload` redundante dentro de `with_lock` — removido.
- **QC-04** · String literal `'Channel::Wavoip'` em vez de `INBOX_TYPES.WAVOIP` — corrigido.
- **QC-05** · Variável `normalized` morta em `ProcessWebhookJob` — renomeada/removida.
- **QC-06** · `assignee_scope` executado duas vezes por query em `assignee_or_fallback` —
  corrigido para reusar a mesma relation.
- **QC-07** · `busy_agents` carregava todos os usuários da conta do Redis — corrigido com
  `OnlineStatusTracker.get_users_with_status` limitado aos IDs elegíveis (`hmget`).
- **QC-08** · `ProcessWebhookJob` na fila `:low` atrasava eventos urgentes de chamada —
  movido para `:default`; `RECORD` processado separadamente em fila de menor prioridade.
- **QC-09** · `DeviceStatusService` fazia dois `channel.reload` consecutivos — consolidado
  em um único reload; adicionado log ao atualizar `phone_number` automaticamente.
- **QC-10** · `mediaByInbox` acumulava estado sem ser limpo no disconnect — `clearWavoipMediaForInbox`
  exportado e chamado dentro de `disconnectWavoipInbox`.
- **QC-11** · `transition_allowed?` permitia transições entre status terminais diferentes
  (ex: `completed` → `no_answer` por webhook atrasado) — bloqueado.
- **QC-12** · `webhook_url` silenciava falta de `FRONTEND_URL` retornando `localhost:3000` —
  corrigido para retornar `nil` e a UI exibir aviso.
- **QC-13** · `onOutboundConnected` era código morto (handler no-op, evento nunca emitido
  pelo backend) — removido.
- **QC-14** · `test_wavoip_webhook` executava o job de forma síncrona (`perform_now`),
  bloqueando thread Puma — trocado para `perform_later`.
