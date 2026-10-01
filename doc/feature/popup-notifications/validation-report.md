# Pop-up e Web Push — validação do candidato

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
