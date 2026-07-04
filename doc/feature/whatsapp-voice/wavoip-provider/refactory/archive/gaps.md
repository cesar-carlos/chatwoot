# Gaps de comportamento — Wavoip (arquivado)

> Conteúdo integral preservado para consulta histórica. Ver [../CHANGELOG.md](../CHANGELOG.md)
> para o resumo condensado. O texto original completo (código antes/depois de cada gap) está
> disponível no histórico do git para este arquivo antes de 04 jul. 2026.

Features implementadas com cobertura incompleta. O fluxo feliz funcionava, mas casos
esperados em produção não eram tratados corretamente.

## Lista de itens (todos corrigidos, exceto onde marcado parcial)

- **GAP-OUTBOUND-01** · Widget outbound sumia enquanto SDK ainda tocava — ✅ Corrigido (26 jun.):
  `isWavoipSdkCallOwned` no frontend + `defer_outbound_ended_broadcast?` no backend.
- **GAP-01** · `offline_fallback: 'none'` não bloqueava a escalação por timeout — ✅ Corrigido
  (26 jun.): `escalated_users` retorna `User.none` quando `offline_fallback == 'none'`.
- **GAP-02** · `accepted_by_agent_id` podia não ser persistido sem erro visível — ⚠️ Parcial
  (04 jul.): retry com backoff implementado; falha após 3 tentativas ainda só loga
  `console.warn` (sem alerta de UI). Backlog: mover a responsabilidade de attribution para o
  backend via `JoiningAgentCache` ao invés de depender do `PATCH` do browser.
- **GAP-03** · Token rotacionado não reconectava o SDK — ✅ Corrigido: `wavoipSdkSyncKey` inclui
  hash do token; `syncConnections` força reconexão quando diverge.
- **GAP-04** · `PhoneNormalizer` assumia Brasil para qualquer inbox com prefixo 55 — ⚠️ Parcial
  (04 jul.): specs BR/US adicionados; `Phonelib` ainda não substitui a heurística `+55` para
  todos os casos LATAM. Backlog: avaliar `Phonelib.parse(phone, country_hint)` completo.
- **GAP-05** · `ring_timeout_seconds` sem limite máximo — ✅ Corrigido: validação `<= 300` no model.
- **GAP-06** · Listener `statusChanged` podia vazar se `device.on()` não retornasse unsubscribe —
  ✅ Corrigido: handler guardado + fallback `device.off`.
- **GAP-07** · `assignee` e `assignee_or_inbox_members` mapeavam para o mesmo resolver —
  ✅ Corrigido: resolver `:assignee_only_scope` dedicado.
- **GAP-08** · `incoming_call_notify_busy_agents` não se aplicava à escalação — ✅ Implementado.
- **GAP-09** · `administratorsToggleDisabled` sem contrato no backend — ✅ Corrigido: frontend
  força `include_admins: false` ao salvar `offline_fallback: 'none'`.
- **GAP-10** · `saveCallRouting` com race last-write-wins — ✅ Corrigido.
- **GAP-11** · `WavoipDevicePanel` fazia polling mesmo com device já conectado na montagem —
  ✅ Corrigido: `onMounted` só chama `startPolling` se `!isConnected.value`.
- **GAP-ADMIN** · Administradores online não recebiam o toque inicial — ✅ Corrigido: introduzido
  `recipients_base_scope` como escopo único de destinatários elegíveis (membros + admins quando
  configurado), usado em `online_member_users`, `busy_agents` e `broad_fallback_scope`.

Itens ⚠️ parciais (GAP-02, GAP-04) permanecem como backlog de baixo risco — não bloqueiam
produção, documentados para retomada futura se o volume de chamadas internacionais crescer.
