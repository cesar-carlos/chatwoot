# Popup visual — Improvements backlog

Itens fora da entrega, revisados em 01/out/2026.

---

## Já entregue

- Coluna Popup (desktop) e seção mobile
- Rótulo fixo “Pop-up notification”, cabeçalho sem sobreposição e rótulos mobile clicáveis
- Fallback móvel via `ServiceWorkerRegistration.showNotification` com o painel ativo
- Flags por conta em `ui_settings.popup_notification_flags_by_account`
- Corpo sem repetir o nome do contato
- Popup com a janela em foco quando a conversa aberta é outra
- Fecha o aviso em `conversation.read`
- Nota na linha de chamada de voz
- Chaves, tags e detecção da conversa visível isoladas por conta
- Persistência estrita com rollback da seleção quando a API falha
- Ação explícita para conceder permissão aos alertas com painel aberto
- Opt-in Web Push independente e persistido por dispositivo
- Specs do helper
- Criação do evento de nova conversa quando somente Pop-up está marcado
- Fechamento de todos os avisos da conversa, inclusive criação pendente no mobile
- Falha de exibição visível uma vez por sessão e preferência por janela da mesma conta no clique
- Bloqueio de salvamentos concorrentes de preferências

---

## P2 — Produto

| ID | Item | Notas |
|----|------|-------|
| PN-P2-2 | Aviso com a PWA do celular suspensa | O sistema congela a página. Continua dependendo da inscrição Web Push neste dispositivo e da coluna Push |
