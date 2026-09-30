# PWA — pendências e melhorias

## Concluído no código

- Manifesto white-label dinâmico nas duas URLs e independente de `DISPLAY_MANIFEST`.
- Ícones Se7e 192×192 e 512×512 configuráveis, opacos, centralizados e `any maskable`.
- Metadados Android/Apple e modo standalone.
- Botão de instalação Chromium e instruções específicas para iOS/iPadOS.
- Opt-in Push explícito por dispositivo, preservação de opt-out, serialização e rotação VAPID.
- Exclusão autenticada de browser Push sem quebrar FCM.
- Payload real e de diagnóstico com corpo, ícone, tag, URL, TTL de 24 horas e urgência alta.
- Worker com payload defensivo, reutilização da janela e proteção de mesma origem.
- Separação visual e funcional entre Push e Pop-up.
- Specs dos fluxos críticos e documentação de rollout.
- Asserção da área segura dos ícones, conferida também diretamente com MiniMagick.
- Vitest isolado por worktree com 19 testes PWA/Push passando; ESLint e RuboCop direcionados passando.
- Verificador público `bin/fork-pwa-smoke` para release, manifesto e ícones.
- Integração no `origin/main` do fork, sem PR ou push para `upstream`, concluída no commit `092c8eeaf7`.

## Pendente operacional e de validação

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Publicar o commit `092c8eeaf7` ou posterior | O `GIT_SHA` do dashboard corresponde ao release novo |
| P0 | Reconciliar produção e fork | Preservar 480 commits exclusivos e as alterações locais do checkout de produção antes de trocar o release |
| P0 | Executar `db:chatwoot_prepare` | As duas configurações de ícone existem no Super Admin |
| P0 | Configurar ícones Se7e | URLs públicas retornam PNG nos tamanhos declarados |
| P0 | Invalidar caches antigos | `/manifest.json` e `/manifest.webmanifest` entregam o mesmo JSON dinâmico |
| P0 | Validar Android e iOS | Instalação standalone e Push com app fechado funcionam |
| P1 | Executar RSpec com banco autenticado | Specs Ruby direcionados passam; RuboCop já passou |
| P1 | Monitorar entrega | Jobs, inscrições expiradas e diagnósticos não mostram regressão |

## Melhorias futuras, fora do escopo

- Experiência offline, que exige projeto próprio de cache, autenticação e atualização.
- Métrica de conversão do botão de instalação, caso haja necessidade de produto.
- Diagnóstico de permissões por fabricante Android, se surgirem incidentes reproduzíveis.

Não adicionar polling em segundo plano, Firebase para a PWA ou tentativa de manter o WebSocket vivo durante suspensão. Esses mecanismos não substituem Web Push e aumentam consumo de bateria e complexidade.
