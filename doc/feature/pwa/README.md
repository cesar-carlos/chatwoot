# PWA e Web Push do painel

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

**Estado do código:** integrado ao `origin/main` do fork `cesar-carlos/chatwoot` no commit `092c8eeaf7`, em 30/set/2026. **Produção:** ainda executa o commit anterior `61fc65923d`; requer deploy, configuração, invalidação de cache e validação nos aparelhos descritos em [implementação e publicação](./implementation-plan.md).

> A presença do código no `origin/main` não conclui o rollout. Enquanto o domínio público não entregar o manifesto dinâmico e os dois ícones, o navegador poderá oferecer apenas **Criar atalho** ou informar que o aplicativo não pode ser instalado.

> Em 30/set/2026, o checkout que executa produção também diverge do `origin/main` e contém alterações locais. O release precisa preservar esse trabalho antes de trocar o código em execução.

| Recurso | Implementação |
|---------|---------------|
| Manifesto white-label | `/manifest.webmanifest`, com `/manifest.json` como alias dinâmico |
| Instalação | Link e metadados PWA presentes mesmo com `DISPLAY_MANIFEST=false` |
| Identidade | `INSTALLATION_NAME`, `BRAND_NAME`, `id: "/"` e modo `standalone` |
| Ícones | PNGs 192×192 e 512×512, opacos, centralizados e `any maskable` |
| Instalação guiada | `beforeinstallprompt` no Chromium e instruções Safari no iOS/iPadOS |
| Web Push | Opt-in explícito por dispositivo, recuperação da inscrição e rotação VAPID |
| Clique no Push | Reutiliza uma janela da mesma origem e navega para a conversa |
| Pop-up | Canal separado, dependente do painel aberto e da conexão em tempo real |
| Verificação do release | `bin/fork-pwa-smoke` confere versão, manifesto e ícones no domínio público |

## Status do rollout

| Etapa | Estado em 30/set/2026 |
|-------|-----------------------|
| Implementação no fork | Concluída e publicada no `origin/main` |
| Documentação | Atualizada com o estado observado |
| Deploy da versão PWA | Pendente |
| Configuração dos ícones | Pendente em produção |
| Validação Android/iOS | Pendente após o deploy |
| Aceite de Push com app fechado | Pendente após o deploy |

## Documentos

- [Estado atual e arquitetura](./current-state.md)
- [Implementação, testes e publicação](./implementation-plan.md)
- [Decisões técnicas](./implementation-decision-tree.md)
- [Pendências operacionais e melhorias futuras](./improvements-backlog.md)

## Requisitos do aparelho

- Android: Chrome atual, HTTPS e manifesto/ícones acessíveis na mesma origem.
- iPhone/iPad: iOS/iPadOS 16.4 ou superior; abrir no Safari, adicionar à Tela de Início e iniciar pelo ícone.
- Push: chaves VAPID válidas, permissão concedida por interação do usuário e inscrição ativa para aquele navegador.

O sucesso do diagnóstico significa que o serviço Push aceitou a mensagem. A exibição final ainda depende do sistema operacional, das permissões e das políticas de energia do aparelho.
