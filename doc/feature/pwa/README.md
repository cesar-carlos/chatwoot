# PWA e Web Push do painel

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

**Estado do código:** histórico 4.18, PWA e alterações locais integrados ao `main` do fork. **Produção:** o domínio público executa o release `6e30bc8c97` desde 30/set/2026; build, migrações, configuração dos ícones e verificação HTTP foram concluídos. A instalação e a entrega de Push com o app fechado ainda precisam ser homologadas em aparelhos reais, conforme [implementação e publicação](./implementation-plan.md).

> O manifesto e os ícones agora são entregues pelo domínio público, mas isso não comprova a experiência em todos os celulares. A homologação exige instalar a PWA e testar uma notificação real com o aplicativo fechado.

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
| Deploy da versão PWA | Concluído no release `6e30bc8c97` |
| Configuração dos ícones | Concluída e verificada pelo domínio público |
| Validação Android/iOS | Pendente em aparelhos reais |
| Aceite de Push com app fechado | Pendente em aparelhos reais |

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
