# Popup visual — Improvements backlog

## Novo candidato de experiência de permissão

Implementados em `feat/guided-push-permission`: convite inicial único na PWA, botões explícitos e ajuda de desbloqueio. As preferências de Pop-up continuam independentes; nenhuma migração ou ativação indiscriminada de eventos foi feita.

Ainda pendentes: homologação de permissão/apresentação em aparelhos, acessibilidade e publicação autorizada do candidato. Detalhes: [PWA](../pwa/improvements-backlog.md).

Itens fora da entrega, revisados em 01/out/2026.

---

## Já entregue

- Coluna Popup (desktop) e seção mobile
- Rótulo fixo “Pop-up notification”, cabeçalho sem sobreposição e rótulos mobile clicáveis
- Fallback móvel via `ServiceWorkerRegistration.showNotification` com o painel ativo
- Flags por conta em `ui_settings.popup_notification_flags_by_account`
- Corpo sem repetir o nome do contato
- Popup com a janela em foco quando a conversa aberta é outra
- Fecha o ID lido em `notification.updated`; `conversation.read` não fecha avisos do agente
- Nota na linha de chamada de voz
- Chaves, tags e detecção da conversa visível isoladas por conta
- Persistência estrita com rollback da seleção quando a API falha
- Ação explícita para conceder permissão aos alertas com painel aberto
- Opt-in Web Push independente e persistido por dispositivo
- Specs do helper
- Criação do evento de nova conversa quando somente Pop-up está marcado
- Fechamento limitado por conta/destinatário/ID, inclusive criação pendente na página e no worker; leitura em lote preserva avisos novos
- Falha de exibição visível uma vez por sessão e preferência por janela da mesma conta no clique
- Bloqueio de salvamentos concorrentes de preferências

## Integrado, publicado no fork e implantado

- Revalidação de acesso/preferências antes do Push e validação das chaves browser na API.
- Ativação do registro correto, cancelamento de requests, timeouts e invalidação da sessão no logout.
- Consulta por conta com erro/retry, respostas antigas descartadas e estado **Verificando** no dispositivo.
- Rotas normalizadas e correção do evento de leitura, inclusive múltiplas abas e limite de lote.
- Diagnóstico restrito ao próprio dispositivo e ações abrir/marcar como lida, sem credenciais no worker.
- Regressões permanentes e [relatório de validação](./validation-report.md).

Integração, publicação no fork e build/deploy concluídos no release `f58ca95d4d`. Homologação desktop/Android/iOS permanece pendente. Não tratar aceitação pelo provedor como confirmação do banner. Resposta direta, silenciamento, cache offline e polling continuam fora do escopo.

---

## P2 — Produto

| ID | Item | Notas |
|----|------|-------|
| PN-P2-2 | Aviso com a PWA do celular suspensa | O sistema congela a página. Continua dependendo da inscrição Web Push neste dispositivo e da coluna Push |
