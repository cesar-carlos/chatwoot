# PWA e Web Push do painel

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

**Estado do código:** a PWA original está no `main` do fork; a revisão dos ícones Icon Kitchen está no branch local `fix/pwa-icons-review`, ainda não integrado nem publicado. **Produção:** o domínio público continua no release `6e30bc8c97` de 30/set/2026, com os ícones antigos. A instalação e a entrega de Push com o app fechado ainda precisam ser homologadas em aparelhos reais, conforme [implementação e publicação](./implementation-plan.md).

> O manifesto e os ícones agora são entregues pelo domínio público, mas isso não comprova a experiência em todos os celulares. A homologação exige instalar a PWA e testar uma notificação real com o aplicativo fechado.

| Recurso | Implementação |
|---------|---------------|
| Manifesto white-label | `/manifest.webmanifest`, com `/manifest.json` como alias dinâmico |
| Instalação | Link e metadados PWA presentes mesmo com `DISPLAY_MANIFEST=false` |
| Identidade | `INSTALLATION_NAME`, `BRAND_NAME`, `id: "/"` e modo `standalone` |
| Ícones no candidato | PNGs Se7e distintos para `any` e `maskable` em 192×192 e 512×512; Apple Touch 180×180 e favicon ICO versionados |
| Instalação guiada | `beforeinstallprompt` no Chromium e instruções Safari no iOS/iPadOS |
| Web Push | Opt-in explícito por dispositivo, recuperação da inscrição e rotação VAPID |
| Clique no Push | Reutiliza uma janela do painel da mesma origem e navega para a conversa |
| Pop-up | Canal separado, dependente do painel aberto e da conexão em tempo real |
| Verificação do release | `bin/fork-pwa-smoke` confere versão, manifesto e bytes dos seis ícones no domínio público |

## Status do rollout

| Etapa | Estado em 1º/out/2026 |
|-------|-----------------------|
| PWA original no fork | Publicada no `origin/main` |
| Revisão Icon Kitchen | Em validação no branch local; ainda não publicada |
| Deploy da versão PWA anterior | Concluído no release `6e30bc8c97` |
| Configuração dos novos ícones | Pendente após o próximo deploy |
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
