# PWA — estado atual

## Revisão do candidato assistido

Estado mais recente: `fix/pwa-assisted-diagnostics-review`, incorporando `feat/mobile-pwa-install-diagnostics`. Não integrado/publicado/implantado; os candidatos anteriores abaixo permanecem como histórico.

- `usePwaInstallation` compartilha consulta e estado **Verificando**. Um `AbortController` limita a operação inteira de manifesto e ícones a dez segundos, cancela downloads restantes e libera a trava. JSON/campos inválidos e ícones ausentes continuam erros de configuração; rede/HTTP 5xx e timeout têm mensagens próprias. **Verificar novamente** exige clique, preserva o evento de instalação disponível e não cria polling.
- `PushDeviceDiagnostics` invalida a apresentação pendente ao fechar o diálogo. Resultado tardio não o reabre nem substitui uma investigação encerrada; desmontagem continua protegida. Fechar não cancela um teste já aceito pelo provedor, que ainda pode chegar ao aparelho.
- `usePushDevice` compartilha a atividade **Verificando / Ativando / Testando / Desativando** entre superfícies. `getPushEnvironment` mantém o contrato `unsupported`, acrescentando `reason` para contexto inseguro, APIs ausentes ou VAPID não configurado.
- `PwaDeviceSettings` recebe somente disponibilidade das preferências e flags Push atuais. Aviso de zero eventos exige inscrição confirmada, consulta da conta bem-sucedida e nenhuma gravação em andamento. O link leva à seção de eventos, com destino acessível por teclado; não altera seleções.
- Dois hooks upstream `FORK:` passam esses dados e identificam o destino. Sem mudança Ruby, API, banco, payload, VAPID, ícones ou regras de Pop-up.

Automação e homologação pendente: [relatório](../popup-notifications/validation-report.md#revisão-do-candidato--02out2026).

## Incremento mobile e diagnóstico assistido

Estado de código: `feat/mobile-pwa-install-diagnostics`, incluindo a ativação guiada anterior; não está na produção.

- `PwaMobileInstallPromotion` exige autenticação, conta carregada/ativa, Android/iOS e ausência de standalone/instalação confirmada. Onboarding não mostra o cartão.
- `usePwaInstallPromotion` mantém a dispensa em `chatwoot:install-promotion:v1:<user_id>`, separada de convite Push e opt-out. Armazenamento indisponível suprime a promoção; as preferências continuam acessíveis.
- `PwaInstallationCard`/`PwaInstallationHelp` são compartilhados pelo painel e preferências. Ajuda usa três passos, branding e cópia apenas do endereço da origem, sem parâmetros privados.
- `usePwaInstallation` compartilha trava e consulta do manifesto/ícones. Consome o prompt antes de aguardar, preserva eventos novos e bloqueia instalação direta diante de erro verificável. `appinstalled` e modo standalone ocultam a promoção; ausência do evento não identifica instalação.
- `usePushDevice.test` e `inspect` compartilham trava com ativação/recuperação. Conferem ambiente, permissão e opt-out antes e após esperas, sincronizam pelo helper existente e usam o endpoint recém-confirmado. Sessão encerrada, identidade alterada e desmontagem invalidam resultados.
- `PushDeviceDiagnostics` apresenta aceitação, confirmação do usuário e ajuda contextual no mesmo diálogo. A investigação após **Não recebi** não envia novo teste.
- `pushDiagnostic` classifica HTTP 401/403, 404, 422, 429, 502, rede e timeout sem atribuir falhas de transporte à permissão. O timeout de ativação do worker mantém a mensagem existente e recebe código interno frontend.
- Não há mudança Ruby, endpoint, payload, VAPID, preferências de eventos, ícones ou banco. Push continua separado de **Pop-up notification**.

## Novo candidato: convite e ajuda de permissão

A branch `feat/guided-push-permission` contém um convite inicial e a nova interface por dispositivo; **não estão no release de produção**.

- `usePushDevice` compartilha ações, bloqueio de concorrência e publicação do estado entre convite/preferências, reutilizando os helpers existentes e seus controles de sessão.
- `usePwaPushInvitation` exige modo standalone, autenticação, conta ativa e suporte; aguarda onboarding, consulta da inscrição e outros diálogos.
- `chatwoot:push-invitation:v1:<user_id>` guarda somente a apresentação local. Não é sincronizado ao servidor, não contém credenciais e não altera `chatwoot_push_enabled`. Limpar o armazenamento pode reapresentar o convite.
- Permissão bloqueada apresenta ajuda Chrome/Edge, Android, iOS/PWA ou genérica. O retorno por foco/visibilidade e a verificação explícita reavaliam a permissão sem polling.
- Recuperação de bloqueado → concedido pode concluir a inscrição, mas respeita opt-out. Conceder permissão apenas para Pop-up não cria inscrição Push.
- Não há novos endpoints, migration, alteração de VAPID, ícones ou protocolo.

## Correções de segurança e entrega em produção

As correções de `fix/notification-delivery-hardening` foram integradas à `main`, publicadas somente no fork e implantadas no release `f58ca95d4d` em 01/out/2026. SDK, assets Rails e dashboard foram compilados em release isolado; web/worker foram reiniciados na mesma versão e o PM2 foi salvo. O smoke público e a comparação da configuração/avatares passaram. Não houve migration. Evidências e homologação pendente: [validation-report.md](../popup-notifications/validation-report.md).

- Push revalida vínculo/conta ativos, políticas de notificação/conversa e preferência do evento antes de compor conteúdo; preferências ausentes encerram o envio normalmente.
- Cadastro browser valida endpoint HTTPS e chaves, aceitando Base64/Base64URL; dados inválidos não transferem nem criam inscrições. FCM continua compatível.
- O helper espera o registro correto ficar ativo (dez segundos), preserva `updateViaCache: 'none'` e pede permissão apenas durante interação explícita.
- Sync tem timeout/cancelamento; o logout invalida operações antigas, aborta requests, tenta remoção local em paralelo à remota e limita a limpeza total a dez segundos.
- Preferências são consultadas por conta, com erro/retry e gravação bloqueada até sucesso; inscrição mostra **Verificando**, sem falso opt-out inicial.
- Teste autenticado do próprio dispositivo, com limite por usuário, e ações abrir/marcar como lida com proteção de destinatário.
- `/sw.js` importa `/notification-worker.js`, servido pelo controller público Custom com `Cache-Control: no-cache`. Invalidar e verificar ambos no próximo deploy.

## Histórico do release em produção

O release `05361df464` foi publicado em 01/out/2026 com os ícones Icon Kitchen, metadados e recuperação dos avatares. Foi substituído por `f58ca95d4d` e permanece disponível para rollback. As seções históricas abaixo descrevem verificações anteriores; a instalação e o Push com app fechado ainda precisam de validação em aparelhos reais.

## Arquitetura implementada

| Peça | Comportamento |
|------|---------------|
| Manifesto | Controller e builder públicos em `custom/`; resposta `application/manifest+json`, cache público de cinco minutos |
| URLs | `/manifest.webmanifest` é canônica; `/manifest.json` entrega o mesmo conteúdo por compatibilidade |
| Identidade | `id`, `start_url` e `scope` em `/`; `name` de `INSTALLATION_NAME`; `short_name` de `BRAND_NAME` |
| Instalação | `display: standalone`, `prefer_related_applications: false`, tema `#2781F6` |
| Ícones publicados | `PWA_ICON_192_URL` e `PWA_ICON_URL` para `any`; `PWA_ICON_192_MASKABLE_URL` e `PWA_ICON_MASKABLE_URL` para `maskable`; `PWA_APPLE_TOUCH_ICON_URL` e `PWA_FAVICON_URL` para HTML |
| HTML | Manifesto, `theme-color`, Apple Touch 180×180, favicon e metadados `mobile-web-app-capable`/Apple independem de `DISPLAY_MANIFEST` |
| Interface | Componente Vue customizado apresenta disponível, instalado, instruções iOS, indisponível, incompatível e erros verificáveis de manifesto/ícone |
| Push | Helper customizado controla opt-in local, inscrição, remoção, concorrência, troca da chave VAPID, logout e sincronização ao retomar a página |
| Backend | Controllers e serviços estendidos por `prepend_mod_with`; o core contém apenas hooks/imports marcados com `FORK:` |
| Worker | Valida payload, mostra título/corpo/ícone/tag e reutiliza apenas janela do painel na mesma origem |

O arquivo estático `public/manifest.json` foi removido. Não há cache offline, polling em segundo plano nem tentativa de manter o WebSocket ativo durante a suspensão.

Os seis novos assets ficam em `/brand-assets/pwa-se7e-v2-*`, sem sobrescrever as URLs antigas que podem estar em cache por cerca de um ano. Os PNGs maskable usam o símbolo original reduzido a 80% sobre o fundo azul `#006B98`, mantendo os pixels claros dentro do círculo central de raio igual a 40% da largura. O arquivo legado `public/apple-touch-icon.png`, antes vazio, também foi preenchido. As URLs novas só aparecerão no manifesto e no HTML após configurar os seis valores no Super Admin; instalações que deixarem as novas opções vazias mantêm o formato anterior do manifesto.

## Comportamento por plataforma

- Chromium: o app captura `beforeinstallprompt`, exibe o botão somente quando o navegador oferece instalação e chama `prompt()` apenas após clique. `appinstalled` atualiza o estado.
- iOS/iPadOS: fora do modo standalone, a interface orienta Safari → Compartilhar → Adicionar à Tela de Início. A inscrição Push fica desabilitada até o app ser aberto pelo ícone.
- Desktop: a mesma PWA e o mesmo fluxo Push continuam disponíveis sem alterar o comportamento do Action Cable.
- Retomada: ao voltar ao primeiro plano, a inscrição Push é revalidada sem polling em segundo plano; a tela de preferências recebe o estado atualizado.
- Logout: o cliente tenta cancelar a inscrição no servidor e no navegador antes de encerrar a sessão, sem registrar um novo worker. A exclusão remota tem limite de dez segundos; uma falha de limpeza não bloqueia o logout, mas é registrada sem expor o endpoint.

## Estado da produção observado

Antes do deploy em 30/set/2026, `chat.se7esistemassinop.com.br` ainda informava `GIT_SHA=61fc65923d`, sem manifesto dinâmico e sem os ícones Se7e. Após o deploy, a verificação pública retornou:

| Verificação | Resultado observado |
|-------------|---------------------|
| Release do dashboard | `GIT_SHA=6e30bc8c97f18bd559cf38c998b4f40b5ca49354` |
| `/manifest.webmanifest` | `200 application/manifest+json`, cache público de cinco minutos |
| `/manifest.json` | `200 application/manifest+json`, alias do manifesto dinâmico |
| Link `rel="manifest"` no HTML | Presente mesmo com `DISPLAY_MANIFEST=false` |
| `/brand-assets/pwa-icon-se7e-192.png` | `200 image/png` |
| `/brand-assets/pwa-icon-se7e-512.png` | `200 image/png` |
| `/sw.js` | `200 text/javascript` |

No release atual, o verificador `bin/fork-pwa-smoke` passou com as quatro entradas do manifesto e os seis assets versionados, incluindo comparação dos bytes públicos com o release local. Respostas HTTP corretas não substituem o teste de instalação no navegador.

Na publicação anterior, web e worker foram iniciados via PM2 no release `05361df464`, com configuração salva para reboot. `db:chatwoot_prepare` não encontrou migrações pendentes e criou as quatro configurações adicionais de ícones. As seis URLs Icon Kitchen foram configuradas; `DISPLAY_MANIFEST=false` e as chaves VAPID foram preservados. O backup `chatwoot_production_pre_eb93455e4a_20261001.dump` foi validado antes daquela mudança; os releases anteriores permanecem disponíveis para rollback.

### Recuperação dos uploads em 01/out/2026

O release `60ee71940d` havia sido iniciado sem o vínculo de `storage` com `/root/chatwoot/storage`. Dos 8.137 avatares cadastrados no diagnóstico, 8.128 estavam no diretório compartilhado e nove somente no release novo. A pasta nova também recebia outros uploads, totalizando 251 arquivos na pausa dos serviços. Todos foram copiados sem sobrescrever arquivos antigos, com comparação SHA-256, e o diretório original foi preservado em `.codex/backups/storage_60ee71940d_before_shared_20261001`.

Após restabelecer o vínculo compartilhado, os 8.137 avatares estavam acessíveis no storage ativo e as quatro fotos informadas no incidente retornaram HTTP 200. O hotfix acrescentou uma validação na configuração PM2: o release precisa apontar para o storage persistente antes de iniciar. O caminho padrão neste host é `/root/chatwoot/storage`; pode ser definido por `CHATWOOT_SHARED_STORAGE_PATH` ao carregar a configuração PM2.

Na verificação final do release `05361df464`, havia 8.138 avatares e nenhum arquivo ausente no storage ativo. As quatro fotos antigas e uma foto recente retornaram HTTP 200. O smoke público, os dois exemplos RSpec de HTML, os sete testes Vitest de instalação e os lints direcionados passaram; a validação PM2 foi exercitada com um caminho compartilhado e outro isolado.

## Validação do código

- ESLint direcionado e RuboCop dos arquivos alterados passaram em 30/set/2026.
- Os 19 testes Vitest de Push, instalação, worker e preferências passaram com a configuração `custom/vitest.pwa.config.ts`, que resolve os setup files dentro do worktree.
- A revisão Icon Kitchen valida dimensões e opacidade de cinco PNGs, a integridade do ICO e ausência de pixels claros fora da área segura nos dois maskables derivados dos ícones regulares.
- No candidato de release reconciliado, 18 exemplos RSpec passaram em sete arquivos, usando `chatwoot_pwa_release_test` e Redis DB 14 isolados. O Ruby 3.4.4 está disponível via RVM; `rbenv` não está instalado.
- RuboCop passou nos 22 arquivos Ruby alterados, e ESLint passou nos JS/Vue alterados. O build Vite de produção passou após incorporar todas as alterações locais, incluindo a correção de sintaxe de `ConversationCard.vue`.
- O comando `bin/fork-pwa-smoke` passou no domínio público após o deploy do commit `6e30bc8c97`.

Na publicação de 01/out/2026, 29 RSpec de PWA/Push/Pop-up, 40 RSpec de workflow/permissões/histórico e 67 testes Vitest direcionados passaram em banco/Redis de teste isolados. O build de produção, RuboCop do hook corrigido, `git diff --check` e o verificador HTTP atualizado passaram. Uma falha detectada nos RSpec do builder de Pop-up foi corrigida no commit `60ee71940d` antes do deploy.

O release `f58ca95d4d` está em execução e o anterior `05361df464` foi preservado para rollback. A homologação final em aparelhos reais continua pendente.

## Critério de aceite

O domínio público entrega ambos os manifestos com quatro entradas de ícone e os seis assets versionados. O Chrome Android deve oferecer **Instalar** e abrir o painel sem barras do navegador. No iOS/iPadOS 16.4+, a instalação pela Tela de Início deve abrir em standalone. Uma mensagem elegível deve gerar Push com a PWA fechada, e o clique deve reutilizar a PWA aberta ou criar uma janela na conversa correta. Os critérios de aparelho e entrega final de Push ainda não foram homologados.
