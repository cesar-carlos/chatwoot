# Pop-up e Web Push — validação do candidato

## Integração das notificações por time — 02/out/2026

Após `git fetch origin`, somente `feat/team-unassigned-notifications` (`f3e91283ff`) e `fix/team-notification-hardening` (`5dc0fb450b`) estavam fora da main local. A segunda contém a primeira. O worktree `fix/integrate-team-notifications-main` foi criado de `origin/main` atualizado e avançado por fast-forward à main anterior `b4334fdc0f` e ao candidato `5dc0fb450b`, sem conflitos. A main recebe a integração e este registro documental; branches e worktrees antigos foram preservados.

| Verificação da integração | Resultado |
|--------------------------|-----------|
| Implementação integrada | Árvore idêntica ao candidato validado; somente documentação de status alterada nesta etapa |
| Testes/lint | Evidências do candidato abaixo preservadas: 228 exemplos Ruby, revalidação de 28, 289 testes frontend e lint dirigido sem infrações; não reexecutados nesta integração sem mudança de código |
| `git diff --check` | Sem erros |
| Inventário `FORK:` | 666 → 684; 18 novas identidades no conjunto da regra/revisão, nenhuma anterior removida |
| Auditoria de branches | Todas as referências locais e `origin/*` contidas na main após a integração; nenhuma pendência adicional |
| GitHub/build/deploy/serviços | Não realizados ou alterados nesta etapa |
| Homologação em aparelhos | Continua pendente |

As menções a branch fora da main nas seções de validação abaixo descrevem o momento dos testes, não o estado após esta integração. A falha preexistente de exclusão de mensagens continua registrada, sem alteração fora do escopo. Nenhuma migration ou operação em banco/Redis foi necessária para integrar.

## Revisão de segurança e idempotência — 02/out/2026

Candidato `fix/team-notification-hardening`, criado de `origin/main` recém-consultado e avançado por fast-forward a `feat/team-unassigned-notifications` (`f3e91283ff`). A main local continua `b4334fdc0f`; produção, GitHub, build e serviços não foram alterados. Esta seção substitui as evidências do candidato inicial para os contratos revisados, sem apagar o histórico abaixo.

- Autorização em SQL antes da paginação, compartilhada por histórico, contadores, operações individuais, leituras em lote e conteúdo dos eventos. Regressões com perda de time/conta, conta suspensa, papéis customizados e comparação com `ConversationPolicy`, sem eliminar histórico ainda autorizado.
- Identidade por transição, preservada no evento e na notificação: dois workers PostgreSQL simultâneos, job repetido, retry parcialmente concluído, rollback e aviso apagado pela limpeza não duplicam a criação. Eventos antigos na sequência A → B → A são descartados. Não é uma garantia de entrega exatamente uma vez pelo provedor Push.
- Nome do time preservado desde a atribuição, inclusive quando renomeado antes do job. Estado interno protegido contra escrita do cliente e omitido nos payloads, mudanças de webhook e API de mensagens; evento assíncrono original não é mutado pela sanitização.
- Explicação da regra nas preferências desktop e nos três canais mobile; traduções en/pt_BR, sem seleção automática de eventos ou mudança de inscrição Push.

| Verificação da revisão | Resultado |
|-----------------------|-----------|
| RSpec amplo dirigido | 228 exemplos, zero falhas; OSS, Enterprise, Custom, webhooks, finder e GET de mensagens |
| Revalidação da matriz de acesso | 28 exemplos, zero falhas; inclui administrador com papel customizado, adicionado após a execução ampla |
| Vitest | 289 testes em 29 arquivos, zero falhas; inclui montagem das quatro superfícies de ajuda |
| RuboCop | 28 arquivos Ruby/Jbuilder, sem infrações |
| ESLint | Seis arquivos JS/Vue, sem erros ou avisos |
| Traduções e whitespace | JSON en/pt_BR válidos; `git diff --check` sem erros |
| Inventário de marcadores | 675 → 684; nove novas identidades, nenhuma anterior removida |
| Homologação em dispositivos/acessibilidade | Pendente; não inferida dos testes automatizados |
| Main/GitHub/build/deploy | Não executados neste incremento |

O RSpec foi executado exclusivamente com `RAILS_ENV=test`, banco novo `chatwoot_team_notification_hardening_test` e Redis temporário em `127.0.0.1:16479`. O teste de concorrência usa conexões distintas e remove suas próprias notificações antes da exclusão assíncrona dos proprietários. Um fixture órfão dessa limpeza foi removido apenas do banco dedicado, sem acesso aos dados de produção. Banco de teste mantido para repetição; Redis temporário encerrado ao concluir a validação. Não houve migração de produção nem envio real de e-mail/Push.

Antes de Ruby/Bundler foi tentado `eval "$(rbenv init -)"`; `rbenv` não está instalado. Foi usada a Ruby 3.4.4 já disponível, correspondente à versão do projeto. Dependências frontend instaladas offline com lockfile congelado. Avisos de enums Rails/Browserslist são preexistentes.

### Escopo dos testes e falha preexistente

Além dos 14 arquivos da validação inicial abaixo, foram executados:

```text
spec/custom/services/custom/notification/accessible_scope_spec.rb
spec/custom/services/custom/notification/team_assignment_transition_spec.rb
spec/custom/services/custom/notification/team_assignment_concurrency_spec.rb
spec/custom/controllers/custom/api/v1/accounts/notification_history_access_spec.rb
spec/custom/services/custom/notification/bulk_read_service_spec.rb
spec/custom/listeners/custom/action_cable_listener_spec.rb
spec/custom/listeners/custom/base_listener_spec.rb
spec/custom/presenters/conversations/event_data_presenter_spec.rb
spec/controllers/api/v1/accounts/notifications_controller_spec.rb
spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb:185
spec/finders/notification_finder_spec.rb
spec/listeners/webhook_listener_spec.rb
```

O fixture de `NotificationFinder` agora usa administrador para testar ordenação/filtros com acesso real; agentes sem membership não devem enxergar essas conversas. Os novos specs Custom cobrem as restrições, em vez de enfraquecer a autorização para satisfazer o fixture antigo.

A execução exploratória do arquivo inteiro `messages_controller_spec.rb` encontrou uma expectativa de apagar `bcc_emails` ao excluir mensagem (linha 233). O mesmo exemplo falha no candidato anterior `f3e91283ff`: o overlay de exclusão já preserva `content_attributes`. Esse comportamento não pertence à regra de time e não foi alterado; a suíte final cobre o GET afetado e a regressão Custom da resposta pública. Não declarar a suíte completa do projeto validada.

### Aceite manual e publicação pendentes

- Desktop, Android/PWA e iOS instalado: preferências longas, foco/teclado/leitor de tela e entrega de notificação real com o app fechado; Pop-up apenas com painel conectado e conversa diferente.
- Trocar time A → B → A rapidamente, retirar/recolocar agente e repetir processamento: somente a transição atual gera o aviso, uma criação por membro.
- Renomear time antes do job e depois da entrega: título preserva o nome original. Perder acesso e atualizar sino: lista e contadores não exibem a conversa; histórico volta apenas se o acesso for restabelecido.
- Reabrir sem mudança de time/agente: não gerar aviso adicional. Esse gatilho opcional não foi aprovado.
- Integração/publicação/deploy exigem autorização separada. Novo build frontend e mesma versão em todas as instâncias web/workers; sem migration, alteração VAPID ou nova configuração. Não reinterpretar eventos legados sem revisão como atribuições novas.

## Regra de time sem agente — 02/out/2026

Candidato `feat/team-unassigned-notifications`, criado após `git fetch origin main` e avançado por fast-forward à main local `b4334fdc0f`. Nenhuma alteração na main, GitHub ou produção nesta etapa. Testes usam exclusivamente `RAILS_ENV=test`, banco dedicado `chatwoot_team_notifications_test` e Redis temporário em `127.0.0.1:16479`, sem reutilizar o serviço de produção.

Cobertura nova: gatilho real de atribuição ao time/remoção de agente, seleção independente, Pop-up-only, conta/time errado, vínculo removido, políticas customizadas, agente/bots, estado/contato bloqueado, simultaneidade de eventos, evento atrasado, captura do time original, título localizado, flags aditivas, API por conta, payload Push e revalidação de e-mail na renderização. Dois fixtures antigos de `ConversationPolicy` usavam a associação removida `assignee_agent_bot`; foram atualizados para `ai_assignee`, sem mudar as políticas.

| Verificação do incremento | Resultado |
|---------------------------|-----------|
| RSpec dirigido, OSS/Enterprise/Custom | 128 exemplos, zero falhas; 34 exemplos novos em `spec/custom` |
| Vitest dirigido | 285 testes em 28 arquivos, zero falhas |
| RuboCop | 16 arquivos Ruby, sem infrações |
| ESLint | 6 arquivos JS/Vue, sem erros ou avisos |
| Traduções | Quatro JSON válidos; cópia backend en/pt_BR exercitada nos specs |
| `git diff --check` | Sem erros |
| Inventário `FORK:` | 666 → 675; nove hooks/marcadores novos, nenhuma identidade anterior removida |
| Main/GitHub/build/deploy | Não realizados neste incremento |
| Aparelhos/layout/acessibilidade reais | Aceite manual pendente |

Dependências instaladas offline com lockfile congelado, sem alterar versões. Os avisos Rails de enums legados e Browserslist desatualizado não são falhas da nova regra. O Redis temporário foi encerrado após os testes; o banco dedicado de teste permanece disponível para repetir a validação.

### Comandos dirigidos

Antes de Ruby/Bundler foi tentado `eval "$(rbenv init -)"`. `rbenv` não está instalado neste servidor; foi usada a versão já disponível Ruby **3.4.4**, correspondente a `.ruby-version`, com o bundle existente. Mailer está em modo de teste, sem envio externo.

```bash
bundle exec rspec \
  spec/custom/listeners/custom/notification_listener_spec.rb \
  spec/custom/models/custom/team_notification_spec.rb \
  spec/custom/services/custom/notification/team_assignment_eligibility_spec.rb \
  spec/custom/mailers/custom/agent_notifications/conversation_notifications_mailer_spec.rb \
  spec/custom/controllers/custom/api/v1/accounts/team_notification_settings_spec.rb \
  spec/custom/builders/custom/notification_builder_spec.rb \
  spec/custom/services/custom/notification/delivery_access_spec.rb \
  spec/listeners/notification_listener_spec.rb spec/models/notification_spec.rb \
  spec/mailers/agent_notifications/conversation_notifications_mailer_spec.rb \
  spec/controllers/api/v1/accounts/notification_settings_controller_spec.rb \
  spec/services/notification/push_notification_service_spec.rb \
  spec/custom/policies/custom/conversation_policy_spec.rb \
  spec/enterprise/policies/conversation_policy_spec.rb

pnpm exec vitest run --config custom/vitest.pwa.config.ts \
  spec/custom/javascript/dashboard \
  custom/app/javascript/dashboard/components/pwa/specs \
  custom/app/javascript/dashboard/helper/specs \
  custom/app/javascript/dashboard/composables/specs/usePopupNotifications.spec.js \
  custom/app/javascript/dashboard/composables/specs/usePwaInstallation.spec.js \
  app/javascript/dashboard/store/modules/specs/notifications \
  app/javascript/dashboard/api/specs/notifications.spec.js \
  --poolOptions.threads.singleThread --no-coverage
```

RuboCop usa `--config .rubocop.yml` e somente os Ruby alterados; ESLint usa `--no-eslintrc --config .eslintrc.js` e somente JS/Vue alterados. `git diff --check` e inventário também são obrigatórios. Comandos Ruby acima pressupõem credenciais de **teste**, `POSTGRES_DATABASE=chatwoot_team_notifications_test`, `REDIS_URL=redis://127.0.0.1:16479/0` e `SMTP_ADDRESS=test.invalid`; não usar `.env` de produção como ambiente de execução.

### Aceite manual pendente

- Em desktop/mobile, selecionar somente a nova linha em cada canal e atribuir conversa aberta a time com autoatribuição desabilitada: membros autorizados recebem; não membros não recebem.
- Atribuir agente, bot ou time diferente antes do processamento: não entregar o aviso obsoleto. Remover agente mantendo time: gerar um novo aviso. Mudança simultânea de time/remoção de agente: um só aviso por membro.
- Conferir rótulo/ícone no sino, texto longo sem quebra do layout mobile, título com time e corpo com contato; abrir/marcar como lida continuam no fluxo existente.
- Push em Android/PWA e iOS instalado com app fechado; Pop-up somente com painel conectado e conversa diferente. Teste automatizado/provedor não comprova exibição real no aparelho.
- Para publicação futura: merge e build autorizados separadamente, web/workers na mesma versão. Nenhuma migration ou alteração de configuração/chaves requerida.

## Integração na main local — 02/out/2026

Após `git fetch origin`, o worktree `fix/integrate-pwa-assisted-main` foi criado de `origin/main` (`f58ca95d4d`), avançado à main local anterior (`3645eed87f`) e ao candidato final (`063ee874a1`). Ambos os merges foram fast-forward, sem conflitos ou alteração do código testado. A main recebe essa integração e o registro documental.

As três branches pendentes eram `feat/guided-push-permission`, `feat/mobile-pwa-install-diagnostics` e `fix/pwa-assisted-diagnostics-review`; a última contém as outras duas. Todas as demais referências locais e remotas `origin/*` já estavam contidas na main. Nenhuma branch foi apagada ou publicada; worktrees existentes estavam limpos e foram preservados.

| Verificação da integração | Resultado |
|--------------------------|-----------|
| Vitest, comando da seção mobile abaixo | 282 testes em 27 arquivos, zero falhas |
| ESLint dos JS/Vue entre `3645eed87f` e o candidato | 33 arquivos, sem erros ou avisos |
| `git diff --check` da integração | Sem erros |
| Inventário `FORK:` | 657 → 666; nove hooks novos, nenhuma identidade anterior removida |
| Ruby, banco e Redis | Sem alterações ou execução |
| GitHub, build e deploy | Não realizados nesta etapa |
| Homologação em aparelhos/acessibilidade | Continua pendente |

Dependências foram instaladas offline com lockfile congelado no worktree isolado; nenhuma dependência foi alterada. A comparação do inventário normalizou somente números de linha. Auditoria final por ancestralidade verifica todas as branches locais e remotas do fork contra a main; mirrors e backups já contidos não exigem nova integração. A produção documentada abaixo não foi alterada.

## Revisão do candidato — 02/out/2026

Branch `fix/pwa-assisted-diagnostics-review`, criada após fetch de `origin/main` em `f58ca95d4d` e acrescida por fast-forward do candidato mobile `6ea66dedfc`. **Sem merge na main, GitHub, build ou deploy.** Nenhuma alteração Ruby, banco/Redis, serviço ou permissão de produção.

| Verificação deste incremento | Resultado |
|-----------------------------|-----------|
| Vitest direcionado, comando completo abaixo | 282 testes em 27 arquivos, zero falhas |
| ESLint direcionado | 14 arquivos JS/Vue, sem erros ou avisos |
| JSON en/pt_BR | 13 novas chaves nos dois idiomas |
| `git diff --check` | Sem erros |
| Inventário `FORK:` | 664 → 666; dois hooks nas preferências, sem remoção de identidades anteriores |
| Ruby/RSpec/RuboCop | Não se aplicam: nenhuma alteração Ruby |
| Aparelhos e acessibilidade reais | Não homologados nesta etapa |

O comando Vitest é o mesmo da seção mobile abaixo; ESLint usa `pnpm exec eslint --no-eslintrc --config .eslintrc.js <14 arquivos JS/Vue alterados>`. Dependências/lockfile não foram alterados. A primeira execução terminou com os testes aprovados, mas falha de escrita de cache por sandbox; a repetição com permissão para os artefatos do worktree confirmou conclusão sem erro.

Novas regressões: fechamento durante teste pendente e desmontagem; atividades compartilhadas de consulta/ativação/envio/desativação; motivos de ambiente indisponível sem envio; abort real em dez segundos de manifesto e downloads paralelos; conexão/HTTP 5xx versus JSON/ícone inválido; retry explícito sem consumir o evento nativo. Aviso de eventos cobre carga incompleta/falha, conta diferente, inscrição desligada e salvamento, inclusive montagem do componente legado com store Vuex.

### Homologação ainda necessária

- Chrome/Edge desktop, Chrome Android/PWA e iOS/iPadOS 16.4+: instalar, permitir/desbloquear, testar e receber mensagem elegível com app fechado/tela bloqueada.
- Fechar diagnóstico com teste pendente: não reabrir após resposta. A entrega solicitada ainda pode ocorrer; **Não recebi** não deve reenviar automaticamente.
- Interromper/restabelecer conexão: consulta libera após timeout, mensagem distingue rede/configuração e retry restaura disponibilidade sem prompts automáticos.
- Conta sem eventos Push: aviso somente após carga; link abre a seleção. Troca de conta, falha de consulta e salvamento não podem gerar aviso falso; nenhuma flag é selecionada automaticamente.
- Verificar HTTPS/APIs/configuração em ambiente de teste, sem alterar produção; conferir mensagens e ausência de falso pedido de desbloqueio.
- Teclado, Escape, foco do diálogo/link, leitor de tela, contraste e rolagem em viewport pequeno.

Os testes automatizados validam estado/lógica, não banner do sistema ou acessibilidade real. Aceitação pelo provedor e confirmação do usuário continuam conceitos distintos.

## Instalação mobile e teste assistido — 02/out/2026

Branch `feat/mobile-pwa-install-diagnostics`, criada de `origin/main` atualizado em `f58ca95d4d` e acrescida por fast-forward do candidato `feat/guided-push-permission` até `e05e1b4daa`. Inclui o commit local de documentação `3645eed87f`. **Sem merge na main, publicação no GitHub, build de produção ou deploy.** A produção e o histórico abaixo não foram alterados.

| Verificação deste incremento | Resultado |
|-----------------------------|-----------|
| Vitest direcionado, incluindo stores/API legados | 243 testes em 23 arquivos, zero falhas |
| ESLint direcionado | 17 arquivos JS/Vue alterados, sem erros ou avisos |
| JSON en/pt_BR | 36 novas chaves presentes nos dois idiomas |
| `git diff --check` | Sem erros |
| Inventário `FORK:` | 661 → 664; três hooks de App.vue, nenhuma identidade anterior removida |
| Ruby/RSpec/RuboCop | Não se aplicam: nenhuma alteração Ruby |

Comando completo usado no worktree:

```bash
pnpm exec vitest run --config custom/vitest.pwa.config.ts \
  spec/custom/javascript/dashboard \
  custom/app/javascript/dashboard/components/pwa/specs \
  custom/app/javascript/dashboard/helper/specs \
  custom/app/javascript/dashboard/composables/specs/usePopupNotifications.spec.js \
  custom/app/javascript/dashboard/composables/specs/usePwaInstallation.spec.js \
  app/javascript/dashboard/store/modules/specs/notifications \
  app/javascript/dashboard/api/specs/notifications.spec.js \
  --poolOptions.threads.singleThread --no-coverage
```

ESLint: `pnpm exec eslint --no-eslintrc --config .eslintrc.js <17 arquivos JS/Vue alterados>`. O inventário foi comparado normalizando somente os números de linha. Dependências vieram do cache, sem mudança de lockfile; nenhum banco, Redis, serviço ou permissão de produção foi usado/modificado.

As novas regressões em `spec/custom/javascript/dashboard` cobrem Android com/sem evento, iOS, navegadores integrados, cópia de endereço, desktop/standalone, conta carregada, dispensa por usuário e armazenamento indisponível. Também cobrem consumo único e falha do prompt, preservação de evento novo, validação compartilhada e bloqueio por manifesto/ícones inválidos.

O diagnóstico cobre permissão revogada após carregar/aguardar, endpoint alterado, inscrição ausente, recuperação explícita e opt-out preservado; nenhum teste é enviado nos impedimentos locais. Inclui aceitação estrita, Recebi/Não recebi, ajuda adequada, códigos HTTP, timeout, concorrência, logout e desmontagem. A última superfície consegue concluir a consulta quando a primeira é desmontada.

Durante a ampliação da suíte, o spec Custom de Pop-up deixava a URL da conta ativa no ambiente compartilhado, fazendo nove asserções legadas da API falharem somente no conjunto. A API isolada passou; o spec agora restaura a URL após cada teste. A suíte completa acima passou após essa correção de isolamento, sem alterar o contrato da API.

Diálogos têm nome acessível, região de atualização e rolagem limitada pelo design system. Testes simulam APIs nativas e não comprovam foco real, leitor de tela, contraste visual, instalação ou exibição do aviso. A base Browserslist desatualizada gerou aviso já existente, sem falhas nem atualização de dependências.

### Homologação obrigatória pendente

- Chrome/Edge desktop: instalar pelas preferências, permitir/desbloquear, testar, confirmar Recebi/Não recebi e conferir falhas de sessão/limite.
- Android/Chrome/PWA: cartão inicial, prompt nativo/manual, Agora não persistido, navegador integrado, cópia do endereço e Push com app fechado/tela bloqueada.
- iOS/iPadOS 16.4+: ajuda Safari/Tela de Início, Abrir como App quando disponível, ausência do cartão em standalone, autorização após clique e Push com app fechado.
- Todos: teclado/Escape, foco e retorno de foco, leitor de tela, contraste e rolagem em tela pequena. Conferir que Pop-up continua independente e eventos não são selecionados automaticamente.

Aceitação pelo serviço, inscrição e permissão válidas não demonstram apresentação pelo sistema nem detectam universalmente Foco/Não Perturbe. Merge/GitHub/build/deploy continuam sujeitos a autorização separada. Instruções de instalação conferidas em [web.dev](https://web.dev/articles/customize-install) e [Apple](https://support.apple.com/pt-br/guide/iphone/iphea86e5236/ios).

## Ativação guiada — candidato de 02/out/2026

Branch `feat/guided-push-permission`, criada de `origin/main` em `f58ca95d4d` após fetch e acrescida do commit local de documentação `3645eed87f`. Este incremento **não foi integrado à main, publicado, compilado para produção ou implantado**. O histórico de produção abaixo permanece válido.

A cobertura acrescentada em `spec/custom/javascript/dashboard` exercita convite único por usuário, conta ativa/carregada, exclusão do navegador comum, opt-out, armazenamento indisponível, espera de outros diálogos, fechamento nativo/externo, permissão negada, CTA explícito, recuperação, ações concorrentes e resultados tardios após logout/desmontagem. A suíte existente continua cobrindo worker, VAPID, limpeza, ações e separação de Pop-up.

| Verificação do incremento | Resultado |
|--------------------------|-----------|
| Vitest direcionado | 130 testes em 16 arquivos, sem falhas |
| ESLint direcionado | 18 arquivos JS/Vue/TS, sem erros |
| JSON en/pt_BR | 18 chaves do fluxo disponíveis nos dois idiomas |
| `git diff --check` | Sem erros |
| Inventário `FORK:` | 657 → 661; quatro hooks acrescentados, nenhuma identidade existente removida |

Comando de regressão no worktree:

```bash
pnpm exec vitest run --config custom/vitest.pwa.config.ts \
  spec/custom/javascript/dashboard \
  custom/app/javascript/dashboard/components/pwa/specs \
  custom/app/javascript/dashboard/helper/specs \
  custom/app/javascript/dashboard/composables/specs/usePopupNotifications.spec.js \
  custom/app/javascript/dashboard/composables/specs/usePwaInstallation.spec.js \
  --poolOptions.threads.singleThread --no-coverage
```

ESLint usa `--no-eslintrc --config .eslintrc.js` para não herdar outra instalação de plugins do diretório pai. A configuração PWA existente mantém os arquivos de setup no worktree. Dependências foram instaladas do cache, sem mudança de lockfile. Nenhum banco, Redis, serviço ou permissão de usuário de produção foi modificado.

Não há alterações Ruby: RSpec/RuboCop não se aplicam a este incremento exclusivamente frontend. Testes automatizados usam Notifications API, transporte e fechamento nativo simulados; **não comprovam** o prompt real, foco de teclado, leitor de tela, layout visual ou apresentação do banner pelo sistema.

Pendências de homologação: Chrome/Edge desktop, Android/PWA e iOS/iPadOS 16.4+, cobrindo primeira abertura, Agora não e reabertura, desbloqueio manual, escolha dos eventos e Push com app fechado. Merge/GitHub/build/deploy exigem autorização separada.

Referências para instruções de permissão: [Chrome](https://support.google.com/chrome/answer/3220216?hl=pt-BR), [Edge](https://support.microsoft.com/en-us/edge/manage-website-notifications-in-microsoft-edge), [iOS](https://support.apple.com/pt-br/120681) e [WebKit: interação direta na PWA](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/).

## Histórico: candidato anterior em produção

Data: 01/out/2026. Branch: `fix/notification-delivery-hardening`, criado de `origin/main` no commit `c3796412992f3996bea5b7735be7e5ee4c5c3fa1`.

## Escopo e estado

As correções, diagnóstico por dispositivo, ações e documentação foram implementados no worktree isolado. Em etapa posterior autorizada, os cinco commits até `1b955ad73d` foram incorporados à `main` local por fast-forward em 01/out/2026, sem conflitos ou alteração do código testado. A publicação ocorreu somente em `origin/main` do fork `cesar-carlos/chatwoot`, com SHA remoto conferido. Após nova autorização, o build da `main` em `f58ca95d4d76a6d182bd78e61d3a91fe10db8914` foi implantado em produção, com reinício de web/worker e smoke público concluído. Não houve migration nem troca de ícones/VAPID.

Não foram alterados ícones, manifesto, chaves VAPID, preferências armazenadas ou estruturas do banco. Cadastro/exclusão FCM continuam disponíveis. Não há resposta direta, silenciamento, cache offline, polling ou tentativa de manter o socket ativo durante suspensão.

## Evidências automatizadas

| Verificação | Resultado |
|-------------|-----------|
| RSpec direcionado, incluindo MFA | 71 exemplos, zero falhas e nenhum pendente |
| Vitest, módulos novos e contratos legados | 175 testes em 21 arquivos |
| ESLint | 34 arquivos JS/Vue alterados, sem erros |
| RuboCop | 18 arquivos Ruby alterados, sem infrações |
| `git diff --check` | Sem erros de whitespace |
| `bash -n bin/fork-inventory` | Sintaxe válida |
| Inventário `FORK:` | 638 marcadores na `main` antes do merge; 657 após a integração. O inventário final coincide integralmente com o do candidato validado |

O inventário passou a incluir `public/sw.js`, que contém somente o import do worker Custom. O inventário gerado é um artefato ignorado pelo Git, não um arquivo para publicação.

Os RSpec usaram exclusivamente `RAILS_ENV=test`, banco `chatwoot_pwa_release_test` e Redis DB 14. As chaves de criptografia usadas para os cenários de MFA pertencem apenas ao processo de teste e não substituem configurações de produção. Jobs e entregas externas são simulados pelos specs.

Antes dos comandos Ruby foi tentado `eval "$(rbenv init -)"`. Como rbenv não existe neste host, foi carregado `/usr/share/rvm/scripts/rvm` para usar Ruby 3.4.4. O carregamento do ambiente precedeu as substituições explícitas de banco, Redis e ambiente de teste.

O aviso de Browserslist sobre a base `caniuse-lite` desatualizada não impediu os testes. Não houve atualização de dependências ou lockfile como parte desta correção.

### Cobertura por risco

| Risco corrigido | Regressões |
|-----------------|------------|
| Acesso revogado antes do envio | Vínculo removido, conta suspensa, acesso à caixa/role revogado, nenhum conteúdo composto para destinatário inelegível |
| Preferências removidas | Ausência de registro ou flag encerra o envio sem exceção |
| Inscrição inválida | HTTPS, credenciais na URL, envelope malformado, ponto P-256, segredo de 16 bytes, Base64/Base64URL; nenhuma transferência/persistência parcial |
| Worker ainda instalando | Espera pelo registro correto, ativação e timeout explícito |
| Logout travado | Abort de HTTP, dez segundos no total, fila invalidada, respostas tardias e opt-out/VAPID |
| Preferências carregadas parcialmente | Falha com retry, gravação bloqueada, consulta antiga descartada após troca de conta, rollback |
| Conversa visível em outras rotas | Caixa, equipe, etiqueta, visão personalizada, menções, participantes, não atendidas e inbox-view com parâmetros normalizados |
| Leitura pelo contato removendo aviso | `conversation.read` não fecha; leitura do agente fecha ID exato; lote respeita conta, usuário, conversa e cutoff, preservando novos avisos |
| Clique perdido | Mesma origem, preferência por conta, cliente desaparecido, navegação/foco rejeitados e abertura alternativa |
| Novas interfaces | Diagnóstico restrito ao dispositivo do usuário, três testes/minuto, MFA, erro sanitizado, leitura autorizada/idempotente e intenção consumida uma vez |
| Aviso ainda em criação | Fechamento persistente aguarda exibição pendente, sem remover avisos posteriores |
| Plataformas com/sem ações | Payload antigo compatível; ações limitadas pela plataforma; Pop-up desktop usa worker quando ações são suportadas |

Arquivos Ruby executados: serviços Custom de acesso e lote; request spec `notification_delivery_spec.rb`; modelo Custom de notificação; serviços de Push real/diagnóstico; controllers de inscrição OSS/Custom, notificações, HTML/manifesto e branding; builders de Pop-up e manifesto.

Arquivos frontend executados: helper de Push, ciclo/timeout/logout/retomada, ações, worker; composables de Pop-up e instalação; componentes PWA/preferências; APIs e stores Custom; Action Cable; suites legadas completas dos stores de notificações/preferências e API de notificações.

Configuração do frontend: `pnpm exec vitest run --config custom/vitest.pwa.config.ts <arquivos acima>`. Lints direcionados: `pnpm exec eslint --no-ignore --no-eslintrc --config .eslintrc.js <arquivos alterados>` e `bundle exec rubocop --config .rubocop.yml <arquivos Ruby alterados>`.

## Contratos para a próxima publicação

- `POST /api/v1/notification_subscriptions/test`: autenticado, mesmo guard de MFA do cadastro, endpoint do próprio dispositivo. Entrada inválida: 422; inscrição indisponível: 404; limite: 429; entrega recusada: 502 sanitizado. Sucesso confirma somente aceitação pelo serviço Push.
- `POST /api/v1/accounts/:account_id/notification_actions/:notification_id/read`: usuário/conta atuais, políticas de notificação/conversa, operação idempotente com lock; lê somente o ID indicado.
- `notifications.read`: evento customizado enviado ao destinatário, com `user_id`, conta, conversa opcional e limite de ID aplicado também ao banco.
- `/sw.js` importa `/notification-worker.js`. O segundo endpoint é público, JavaScript e `Cache-Control: no-cache`. Ambos devem ser verificados e invalidados no próximo deploy.
- A ação **Marcar como lida** abre a lista `inbox-view`, não a conversa, para não disparar a leitura automática de outros avisos.
- A intenção de leitura tem nonce em memória, consumo único e duração máxima de 60 segundos. Reinício do worker ou expiração exigem operação manual; não há credenciais no worker nem marcação automática após login.

## Implantação em produção — 01/out/2026

- Release isolado: `/root/chatwoot/.codex/releases/f58ca95d4d`, com `.env` e `storage` vinculados aos caminhos persistentes do host. A configuração PM2 validou o storage antes do início.
- `RAILS_ENV=production bundle exec rails assets:precompile` concluiu SDK, assets Rails e dashboard. Node 24.21.0 e Ruby 3.4.4 via RVM; lockfiles não alterados. Assets antigos com hash foram preservados, sem sobrescrever os novos, para abas abertas durante a troca.
- `chatwoot-web` e `chatwoot-worker` foram reiniciados exclusivamente no novo release. Ambos estavam online, com zero reinícios inesperados; `pm2 save` persistiu o novo diretório para reboot.
- O domínio público confirmou GIT_SHA completo. `bin/fork-pwa-smoke` passou para login, dois manifestos e os seis ícones, incluindo dimensões e comparação dos bytes publicados.
- `/sw.js` e `/notification-worker.js` retornaram HTTP 200 com bytes iguais aos arquivos do release. Ambos usam `Cache-Control: no-cache`; o overlay retorna `application/javascript`. O HTML continua com revalidação e o manifesto mantém cache público de cinco minutos.
- O vhost Nginx recebeu somente uma regra exata para `/sw.js` com `expires -1`, removendo o cache de um ano da entrada. Configuração testada antes/depois e reload concluído. Não houve alteração em outros vhosts; avisos preexistentes de MIME/protocolo não impediram o teste.
- Os dois endpoints POST novos retornaram 401 sem autenticação; nenhum diagnóstico real ou marcação de notificação foi disparado no smoke.
- Antes e depois: 8.162 avatares de contatos, zero arquivos ausentes; amostras antiga/recente retornaram HTTP 200. O fingerprint conjunto de branding/ícones/DISPLAY_MANIFEST/VAPID permaneceu idêntico; `DISPLAY_MANIFEST=false` e nenhuma migration pendente.
- O chunk de dashboard do release anterior continuou retornando HTTP 200. Foram preservados o release `05361df464` e os backups de Nginx/estado PM2 em `.codex/backups/notification-deploy-f58ca95d4d/`, com o dump protegido contra leitura por outros usuários.

Para rollback, validar o storage do release anterior e reiniciar somente os dois apps Chatwoot a partir de seu `ecosystem.config.cjs`, conferir SHA/HTTP e salvar PM2. Recriar esses registros ao trocar diretórios, para não manter `pm_cwd` antigo com args apontando a outro release. Não restaurar globalmente o dump do PM2 se isso puder alterar outros serviços. A regra de revalidação do worker pode ser mantida.

## Homologação ainda pendente

Nenhum teste automatizado confirma a apresentação do banner pelo sistema operacional. Antes de declarar a funcionalidade homologada:

- [ ] Desktop: Push e Pop-up por regra, ações quando disponíveis, nenhuma notificação para conversa já visível.
- [ ] Chrome Android/PWA: mensagem real com app suspenso/fechado e tela bloqueada; clique reutiliza a janela correta.
- [ ] iOS/iPadOS 16.4+ instalado pela Tela de Início: Push real com app fechado/tela bloqueada; navegador comum mostra orientação de instalação.
- [ ] Clique recupera falha de cliente e abre somente URL da mesma origem/conta correta.
- [ ] Leitura individual/batch em múltiplas abas fecha somente os avisos confirmados, preservando notificações novas.
- [ ] Leitura pelo contato não remove o aviso do agente.
- [ ] Ações rejeitam destinatário diferente e acesso revogado; ausência de sessão solicita login sem marcar automaticamente depois.
- [ ] Falha de leitura fica visível e não produz estado otimista irreversível.
- [ ] Logout encerra a sessão mesmo com Push/servidor indisponível.
- [ ] Retomar a PWA reconecta o painel e sincroniza mensagens; diagnóstico não é apresentado como prova de banner.

A integração, publicação do código no GitHub e implantação estão concluídas. Em atualizações futuras, repetir o build isolado e as validações, sem usar os assets do release ativo como saída. A homologação em aparelhos continua obrigatória; monitorar IDs/resultados/classes de erro sem conteúdo, tokens ou endpoint completo.

Veja também [estado do Pop-up](./current-state.md), [plano do Pop-up](./implementation-plan.md), [estado da PWA](../pwa/current-state.md) e [plano da PWA](../pwa/implementation-plan.md).
