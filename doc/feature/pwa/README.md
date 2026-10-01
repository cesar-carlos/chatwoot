# PWA e Web Push do painel

**Candidato em 01/out/2026:** `fix/notification-delivery-hardening` acrescenta autorização no envio, inscrições validadas, logout limitado/cancelável, estado **Verificando**, teste neste dispositivo e ações abrir/marcar como lida. Essa revisão não foi integrada nem implantada. Evidências e critérios de aceite em [validation-report.md](../popup-notifications/validation-report.md); o histórico de produção abaixo descreve o release anterior.

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

**Estado em 01/out/2026:** o release `05361df464` está em produção, com os seis ícones Icon Kitchen configurados, metadados Android/Apple e armazenamento de uploads compartilhado entre releases. Os avatares foram recuperados e verificados pelo domínio público. A instalação e a entrega de Push com o app fechado ainda precisam ser homologadas em aparelhos reais, conforme [implementação e publicação](./implementation-plan.md).

> O manifesto e os ícones agora são entregues pelo domínio público, mas isso não comprova a experiência em todos os celulares. A homologação exige instalar a PWA e testar uma notificação real com o aplicativo fechado.

| Recurso | Implementação |
|---------|---------------|
| Manifesto white-label | `/manifest.webmanifest`, com `/manifest.json` como alias dinâmico |
| Instalação | Link e metadados PWA presentes mesmo com `DISPLAY_MANIFEST=false` |
| Identidade | `INSTALLATION_NAME`, `BRAND_NAME`, `id: "/"` e modo `standalone` |
| Ícones publicados | PNGs Se7e distintos para `any` e `maskable` em 192×192 e 512×512, com símbolo adaptativo na área segura; Apple Touch 180×180 e favicon ICO versionados |
| Instalação guiada | `beforeinstallprompt` no Chromium, instruções Safari no iOS/iPadOS e diagnóstico de manifesto/ícones inacessíveis |
| Web Push | Opt-in explícito por dispositivo, recuperação da inscrição, rotação VAPID, limpeza no logout e revalidação ao voltar ao app |
| Clique no Push | Reutiliza uma janela do painel da mesma origem e navega para a conversa |
| Pop-up | Canal separado, dependente do painel aberto e da conexão em tempo real |
| Verificação do release | `bin/fork-pwa-smoke` confere versão, manifesto e bytes dos seis ícones no domínio público |

## Status do rollout

| Etapa | Estado em 1º/out/2026 |
|-------|-----------------------|
| PWA original no fork | Publicada no `origin/main` |
| Revisão Icon Kitchen | Publicada no release `60ee71940d` |
| Deploy da versão PWA anterior | Preservado no release `6e30bc8c97` para rollback |
| Configuração dos novos ícones | Seis URLs configuradas e conferidas pelo verificador público |
| Correção dos avatares e metadados | Publicada no release `05361df464`; uploads preservados e quatro fotos verificadas com HTTP 200 |
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

O teste do perfil usa apenas a inscrição confirmada deste usuário/dispositivo e limita tentativas a três por minuto. O diagnóstico do Super Admin permanece separado e compatível com o mesmo formato. Ações só aparecem em avisos persistentes reais e em plataformas que as suportam; sem suporte, o clique comum abre a conversa. “Marcar como lida” exige sessão e destinatário correspondentes e não será executado automaticamente após um novo login.

Sem `beforeinstallprompt`, a interface verifica se o manifesto e os PNGs 192/512 respondem corretamente. Mesmo quando respondem, a ausência do evento não revela a causa exata da decisão do Chrome; valide pelo aparelho e pelas ferramentas de instalação do navegador.

O aviso `Banner not shown: beforeinstallpromptevent.preventDefault() called` é esperado: o convite fica disponível pelo botão **Instalar**, que chama `prompt()` após o clique. Erros 404 em `/rails/active_storage/disk/` devem ser investigados como falhas na entrega dos uploads; não são avisos de instalação da PWA.
