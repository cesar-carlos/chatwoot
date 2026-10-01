# Pop-up e Web Push — validação do candidato

Data: 01/out/2026. Branch: `fix/notification-delivery-hardening`, criado de `origin/main` no commit `c3796412992f3996bea5b7735be7e5ee4c5c3fa1`.

## Escopo e estado

As correções, diagnóstico por dispositivo, ações e documentação foram implementados no worktree isolado. Em etapa posterior autorizada, os cinco commits até `1b955ad73d` foram incorporados à `main` local por fast-forward em 01/out/2026, sem conflitos ou alteração do código testado. Os seis commits até `f80a9248cb`, incluindo o registro da integração, foram publicados por push normal somente em `origin/main` do fork `cesar-carlos/chatwoot`; o SHA remoto foi conferido. Não houve build de produção, migration, reinício ou deploy. O release de produção não contém estas correções.

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

A integração e publicação no GitHub do fork estão concluídas. Após autorização de build/deploy, gerar build JS/Vue novo em release isolado, validar storage compartilhado e PM2 antes de iniciar, preservar branding/VAPID, reiniciar web/workers e conferir versão, endpoints e atualização do worker. Não usar o diretório de assets do release atual como saída do build. Manter o release anterior para rollback e monitorar IDs/resultados/classes de erro sem conteúdo, tokens ou endpoint completo.

Veja também [estado do Pop-up](./current-state.md), [plano do Pop-up](./implementation-plan.md), [estado da PWA](../pwa/current-state.md) e [plano da PWA](../pwa/implementation-plan.md).
