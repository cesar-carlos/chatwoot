# Popup visual — Improvements backlog

## Revisão da regra de time — 02/out/2026

Implementados em `fix/team-notification-hardening` e incorporados à main local: autorização do sino/contadores e leituras, criação idempotente sob concorrência/reprocessamento, identidade para eventos atrasados, nome original do time e explicação da regra em desktop/mobile. Novas regressões cobrem esses contratos. A integração contém também `feat/team-unassigned-notifications`; nenhuma outra branch local ou do fork ficou pendente na auditoria de 02/out/2026.

Pendente: homologação desktop/Android/iOS, teclado/leitor de tela/layout, publicação, build e deploy autorizados. Avisar na simples reabertura é opção de produto ainda **não aprovada nem implementada**. [Evidências](./validation-report.md#revisão-de-segurança-e-idempotência--02out2026) e [auditoria da integração](./validation-report.md#integração-das-notificações-por-time--02out2026). As seções anteriores de candidatos abaixo são histórico.

## Pendências após integração local — 02/out/2026

Os candidatos abaixo, até `063ee874a1`, estão incorporados à `main` local. Nenhuma outra branch local/remota do fork requer merge. Continuam pendentes GitHub, build/deploy autorizado e homologação de dispositivos/acessibilidade. As seções anteriores são histórico; [evidências](./validation-report.md#integração-na-main-local--02out2026).

## Revisão assistida — correções implementadas

No candidato local `fix/pwa-assisted-diagnostics-review`, resultados tardios não reabrem diagnóstico fechado; a UI distingue atividades e motivos de ambiente indisponível. Um aviso de zero eventos Push depende da inscrição confirmada e das preferências carregadas, sem alteração automática. Instalação tem validação cancelável e retry explícito. Regras de **Pop-up notification** preservadas.

Pendente: homologar aparelhos, acessibilidade e entrega real; merge/publicação/build/deploy dependem de autorização. Evidências e cenários: [validation-report.md](./validation-report.md#revisão-do-candidato--02out2026).

## Instalação mobile e teste assistido — candidato concluído no código

`feat/mobile-pwa-install-diagnostics` incorpora a ativação guiada e acrescenta verificação fresca, ajuda contextual, recuperação explícita e confirmação **Recebi/Não recebi**. Transporte/provedor/sessão não são confundidos com bloqueio de permissão. As regras e preferências de **Pop-up notification** não mudaram.

Faltam homologação em aparelhos e acessibilidade real, além das etapas autorizadas separadamente de merge/publicação/build/deploy. Não há tentativa de abrir ajustes internos, detectar universalmente Foco ou comprovar banner via resposta da API. Ver [validação](./validation-report.md#instalação-mobile-e-teste-assistido--02out2026).

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
