# PWA — pendências e melhorias

## Correções de `fix/notification-delivery-hardening` publicadas no fork (não implantadas)

- Revalidação de acesso/preferências no envio; preferências ausentes descartam sem retry.
- Inscrição browser validada com HTTPS/P-256/auth, preservando FCM e registros existentes.
- Ativação do worker correto, timeout, cancelamento de sync e logout sem bloqueio por fila.
- Respostas antigas não reativam inscrição nem alteram estado após logout/troca de sessão.
- Preferências por conta, erro/retry, rollback e estado **Verificando**.
- Leitura correta individual/em lote, fechamento de criação pendente e recuperação de cliques.
- Teste neste dispositivo e ações abrir/marcar como lida, com autorização e intenção descartável.
- Worker em `custom/`, com endpoint público revalidável; sem mudança de manifesto, VAPID ou schema.

A integração à `main` e publicação no GitHub do fork estão concluídas. Falta autorizar build/deploy e comprovar critérios em aparelhos: [validation-report.md](../popup-notifications/validation-report.md). Os itens históricos abaixo se referem a releases anteriores.

## Concluído no código

- Manifesto white-label dinâmico nas duas URLs e independente de `DISPLAY_MANIFEST`.
- Ícones Se7e antigos 192×192 e 512×512 configuráveis e `any maskable`, preservados para compatibilidade; a produção usa os ícones Icon Kitchen separados.
- Metadados Android/Apple e modo standalone.
- Botão de instalação Chromium e instruções específicas para iOS/iPadOS.
- Opt-in Push explícito por dispositivo, preservação de opt-out, serialização e rotação VAPID.
- Exclusão autenticada de browser Push sem quebrar FCM.
- Payload real e de diagnóstico com corpo, ícone, tag, URL, TTL de 24 horas e urgência alta.
- Worker com payload defensivo, reutilização de janela e proteção de mesma origem.
- Separação visual e funcional entre Push e Pop-up.
- Specs dos fluxos críticos e documentação de rollout.
- Asserção da área segura dos ícones antigos, conferida também diretamente com MiniMagick.
- Vitest isolado por worktree com 19 testes PWA/Push passando; ESLint e RuboCop direcionados passando.
- Verificador público `bin/fork-pwa-smoke` para release, manifesto e ícones.
- Candidato isolado com 18 exemplos RSpec, 19 Vitest, RuboCop direcionado e build Vite de produção aprovados.
- Integração do histórico 4.18, PWA e alterações locais no `origin/main` do fork, sem PR ou push para `upstream`.
- Deploy do release `6e30bc8c97` em 30/set/2026, com assets compilados, nove migrations aplicadas, ícones configurados e web/worker ativos no PM2.
- Verificação HTTP do login, manifestos, service worker e ícones concluída; `bin/fork-pwa-smoke` passou no domínio público.

## Revisão Icon Kitchen publicada em 01/out/2026

- Novos PNGs versionados 192/512 para `any` e `maskable`, Apple Touch 180×180 e favicon ICO, provenientes do pacote Icon Kitchen fornecido para Se7e.
- Configurações distintas para cada uso, mantendo compatibilidade quando os campos opcionais não estão preenchidos.
- Substituição do Apple Touch raiz que estava vazio; clique do Push passa a priorizar somente uma janela do painel.
- Verificador de release atualizado para comparar as respostas públicas com os bytes dos seis arquivos do release.
- Maskables recompostos com o símbolo claro integralmente dentro da área segura; teste pixel a pixel nos tamanhos 192 e 512.
- Diagnóstico de manifesto/ícones inacessíveis separado da ausência do prompt do navegador.
- Limpeza do Push no logout e revalidação de permissão/inscrição ao voltar ao primeiro plano.
- Candidato validado localmente com 16 exemplos RSpec, 29 testes Vitest, lint direcionado e build Vite de produção.
- Integrado ao `main`, publicado no release `60ee71940d` e configurado em produção; ainda é necessário validar visualmente os ícones em aparelhos Android.

## Pendente operacional e de validação

A correção de 01/out/2026 restaurou o storage compartilhado, preservou 251 uploads novos e validou os 8.137 avatares cadastrados no diagnóstico. O release `05361df464` inclui o metadado genérico de instalação, a validação de persistência no PM2 e a inclusão da configuração PM2 no inventário `FORK:`. O aviso `Banner not shown` é esperado no fluxo pelo botão **Instalar**.

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Validar Android e iOS | Instalação standalone, mensagem real e Push com app fechado funcionam |
| P0 | Validar clique e retomada | Clique abre a conversa certa; app suspenso reconecta e sincroniza ao voltar |
| P1 | Orientar reinstalação de atalhos antigos | Clientes com manifesto ou ícone antigos removem o atalho e instalam novamente |
| P1 | Monitorar entrega | Jobs, inscrições expiradas e diagnósticos não mostram regressão |

## Melhorias futuras, fora do escopo

- Experiência offline, que exige projeto próprio de cache, autenticação e atualização.
- Métrica de conversão do botão de instalação, caso haja necessidade de produto.
- Diagnóstico de permissões por fabricante Android, se surgirem incidentes reproduzíveis.

Não adicionar polling em segundo plano, Firebase para a PWA ou tentativa de manter o WebSocket vivo durante suspensão. Esses mecanismos não substituem Web Push e aumentam consumo de bateria e complexidade.
