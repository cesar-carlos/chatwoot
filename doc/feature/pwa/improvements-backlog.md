# PWA — pendências e melhorias

## Concluído no código

- Manifesto white-label dinâmico nas duas URLs e independente de `DISPLAY_MANIFEST`.
- Ícones Se7e antigos 192×192 e 512×512 configuráveis e `any maskable`, ainda publicados em produção.
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

## Revisão Icon Kitchen em branch local

- Novos PNGs versionados 192/512 para `any` e `maskable`, Apple Touch 180×180 e favicon ICO, provenientes do pacote Icon Kitchen fornecido para Se7e.
- Configurações distintas para cada uso, mantendo compatibilidade quando os campos opcionais não estão preenchidos.
- Substituição do Apple Touch raiz que estava vazio; clique do Push passa a priorizar somente uma janela do painel.
- Verificador de release atualizado para comparar as respostas públicas com os bytes dos seis arquivos do release.
- Ainda não integrado ao `main`, não publicado e não configurado em produção. Os maskables fornecidos têm uma pequena borda clara fora do círculo central de segurança; validar visualmente em aparelhos Android.

## Pendente operacional e de validação

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Publicar revisão Icon Kitchen | Integrar, gerar build limpo, configurar seis URLs, reiniciar serviços e passar no verificador atualizado |
| P0 | Validar Android e iOS | Instalação standalone, mensagem real e Push com app fechado funcionam |
| P0 | Validar clique e retomada | Clique abre a conversa certa; app suspenso reconecta e sincroniza ao voltar |
| P1 | Orientar reinstalação de atalhos antigos | Clientes com manifesto ou ícone antigos removem o atalho e instalam novamente |
| P1 | Monitorar entrega | Jobs, inscrições expiradas e diagnósticos não mostram regressão |

## Melhorias futuras, fora do escopo

- Experiência offline, que exige projeto próprio de cache, autenticação e atualização.
- Métrica de conversão do botão de instalação, caso haja necessidade de produto.
- Diagnóstico de permissões por fabricante Android, se surgirem incidentes reproduzíveis.

Não adicionar polling em segundo plano, Firebase para a PWA ou tentativa de manter o WebSocket vivo durante suspensão. Esses mecanismos não substituem Web Push e aumentam consumo de bateria e complexidade.
