# PWA e Web Push do painel

## Confiabilidade mobile e banners — 02/out/2026

O candidato `fix/mobile-notification-reliability` corrige remoção de inscrição por erro de autenticação e falhas de payload longo, acrescenta aviso genérico de recuperação no worker e diagnóstico **Recebi som ou aviso, mas não apareceu banner**. [Arquitetura](./current-state.md#correções-mobile-e-banners--02out2026), [validação](../popup-notifications/validation-report.md#correções-mobile-e-banners--02out2026).

O Android pode receber com som/tela bloqueada e ocultar o banner flutuante; a ajuda orienta a categoria correspondente. No iPhone, usar iOS/iPadOS 16.4+, abrir pelo ícone da Tela de Início, autorizar e selecionar eventos Push. Banners, Foco e Resumo Agendado também afetam a apresentação. O app não controla esses ajustes do sistema.

`69554d4a89` foi publicado na main do fork; na revisão, produção ainda executava `f58ca95d4d`. As melhorias guiadas integradas e este novo candidato só estarão disponíveis após build/deploy. Aceitação pelo provedor e testes automatizados não comprovam apresentação nos aparelhos; o relato individual do iPhone continua sem causa comprovada.

## Nova regra de time — revisão local de 02/out/2026

`fix/team-notification-hardening` acrescenta a regra de conversa atribuída ao time sem agente, com inscrição e preferências atuais preservadas. Proteções de autorização, reprocessamento e eventos atrasados estão no backend; não alteram o worker, manifesto ou instalação. A explicação da linha existe em desktop e mobile. Incorporada à main local em 02/out/2026, sem GitHub/build/deploy nem homologação em aparelhos. Ver [estado atual](./current-state.md#regra-de-time-sem-agente--candidato-de-02out2026), [validação](../popup-notifications/validation-report.md#revisão-de-segurança-e-idempotência--02out2026) e [integração](../popup-notifications/validation-report.md#integração-das-notificações-por-time--02out2026).

## Integração na main local — 02/out/2026

Ativação guiada, instalação mobile/teste assistido e revisão final (`063ee874a1`) incorporados à `main` local por fast-forward, sem conflitos. As seções de candidatos abaixo registram o histórico anterior à integração. GitHub, build e deploy permanecem pendentes; homologação em aparelhos reais também. [Validação e auditoria de branches](../popup-notifications/validation-report.md#integração-na-main-local--02out2026).

## Revisão do candidato — 02/out/2026

`fix/pwa-assisted-diagnostics-review` incorpora o candidato mobile abaixo e corrige resultados tardios do diagnóstico, consulta de instalação sem limite e mensagens de progresso. Manifesto/ícones têm cancelamento após dez segundos e botão **Verificar novamente**, sem repetição automática. Falhas de conexão não são apresentadas como configuração inválida.

As preferências distinguem HTTPS indisponível, navegador sem suporte e configuração Push ausente. Quando o dispositivo está inscrito, mas a conta não tem eventos Push selecionados, aparece uma orientação para escolhê-los; somente após carregamento bem-sucedido, sem marcar eventos automaticamente.

**Branch local, sem merge, GitHub, build ou deploy.** Testes automatizados não substituem a homologação em aparelhos e acessibilidade. Detalhes: [estado atual](./current-state.md) e [evidências](../popup-notifications/validation-report.md#revisão-do-candidato--02out2026). As seções anteriores abaixo são histórico incorporado.

## Instalação mobile e teste assistido — candidato de 02/out/2026

A branch `feat/mobile-pwa-install-diagnostics` incorpora o candidato `feat/guided-push-permission`. **Não foi integrada à main, publicada, compilada ou implantada.** As seções anteriores sobre candidatos são histórico incorporado; o release de produção permanece `f58ca95d4d`.

O painel autenticado no Android/iOS oferece um cartão de instalação, com dispensa local por usuário. Android usa o prompt disponível; sem ele, oferece instruções. iOS usa Safari → Compartilhar → Adicionar à Tela de Início, incluindo **Abrir como App** quando disponível. Navegadores integrados conhecidos oferecem cópia do endereço. A ausência do evento não prova instalação ou incompatibilidade. A mesma ajuda permanece nas preferências desktop.

O teste revalida permissão, opt-out e inscrição antes de enviar. Bloqueio abre ajuda dentro do aplicativo, não ajustes nativos. Aceitação pelo provedor pergunta **Recebi / Não recebi**; a segunda opção confere novamente os itens locais, sem reenviar automaticamente. Nenhuma verificação universal detecta Foco/Não Perturbe ou comprova a exibição do banner.

Arquitetura e limites: [estado atual](./current-state.md). Evidências e homologação pendente: [validação](../popup-notifications/validation-report.md#instalação-mobile-e-teste-assistido--02out2026).

## Ativação guiada — candidato de 02/out/2026

Implementada na branch `feat/guided-push-permission`, ainda **sem integração, publicação, build ou deploy**. O estado de produção descrito abaixo permanece o release `f58ca95d4d`.

Na primeira abertura autenticada da PWA, um convite oferece **Permitir notificações**, **Ativar neste dispositivo** ou **Como liberar notificações**, conforme a permissão real. **Agora não**, Escape e fechamento externo não alteram preferências nem criam inscrição. O convite aparece uma única vez por usuário neste navegador/PWA; opt-out explícito e inscrição ativa o suprimem.

As preferências também oferecem botões grandes de ativação, ajuda por plataforma e **Já liberei, verificar novamente**. O pedido do navegador só abre após clique. Permissão negada exige liberação nas configurações; o aplicativo não consegue contorná-la. Após ativar, os eventos continuam sendo escolhidos separadamente. Evidências e pendências: [validação](../popup-notifications/validation-report.md#ativação-guiada--candidato-de-02out2026).

**Produção em 01/out/2026:** o release `f58ca95d4d`, compilado da `main` do fork, está em execução em web/worker. Inclui autorização no envio, inscrições validadas, logout limitado/cancelável, estado **Verificando**, teste neste dispositivo e ações abrir/marcar como lida. Build e smoke público passaram; homologação em aparelhos continua pendente. Evidências em [validation-report.md](../popup-notifications/validation-report.md).

O painel pode ser instalado como PWA white-label e receber notificações do sistema com a página suspensa ou fechada. A implementação não tenta manter o Action Cable ativo em segundo plano: celulares podem suspender o WebSocket, e o painel reconecta e sincroniza ao voltar.

**Branding e uploads:** o release atual preserva os seis ícones Icon Kitchen, metadados Android/Apple e storage compartilhado. Após a troca, os 8.162 avatares estavam presentes e amostras antiga/recente retornaram HTTP 200. `05361df464` foi preservado para rollback. A instalação e entrega de Push com o app fechado ainda precisam ser homologadas em aparelhos reais, conforme [implementação e publicação](./implementation-plan.md).

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
