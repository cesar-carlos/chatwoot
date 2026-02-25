# Integracao NotificaMe WhatsApp - Plano Geral

## Objetivo
- Estruturar a implementacao de um canal WhatsApp via NotificaMe no Chatwoot.
- Entregar a nova caixa de entrada com rollout por fases, reduzindo risco de regressao.
- Priorizar primeiro o fluxo funcional minimo (MVP), depois recursos avancados.

## Fonte de Verdade
- Documento consolidado para execucao: `plano-consolidado.md`
- Documentos em `fases/` e `etapas/` permanecem como apoio e detalhamento.

## Escopo Funcional Alvo
- Envio de texto, audio, sticker, documentos/imagens/videos e localizacao.
- Envio de mensagens interativas (botoes, listas e CTA/link).
- Resposta a mensagem (quote/contexto), reacao, typing indicator.
- Download de arquivo criptografado.
- Saude do numero e gestao de bloqueio (listar, bloquear, desbloquear).

## Estrategia Tecnica
- Reaproveitar `Channel::Whatsapp` com novo provider `notificame`.
- Implementar servico provider dedicado para envio e leitura de webhooks.
- Criar configuracao de inbox/canal no dashboard com credenciais da NotificaMe.
- Entregar em fases com criterio de aceite por etapa.

## Referencia Oficial da API
- Documentacao base para consulta obrigatoria em toda etapa: `https://app.notificame.com.br/docs/#/api?id=-whatsapp`
- Regra de execucao: antes de implementar cada funcionalidade, revisar endpoint, payload, autenticacao, limites e erros na documentacao oficial.
- Evidencia minima por item implementado:
  - endpoint validado
  - payload de request validado
  - estrutura de response validada
  - mapeamento de erro para Chatwoot

## Estrutura por Fases
- `fases/fase-1-arquitetura-e-contratos.md` (Sprint 1 - MVP)
- `fases/fase-2-mvp-canal-e-mensagens-base.md` (Sprint 1/2 - MVP)
- `fases/fase-3-interativos-e-recursos-avancados.md` (Sprint 2/3 - MVP estendido + Pos-go-live)
- `fases/fase-4-operacao-e-confiabilidade.md` (Sprint 3 - Pos-go-live prioritario)
- `fases/fase-5-rollout-validacao-e-go-live.md` (Sprint 3 - Go-live)
- `etapas/etapas-api-notificame-whatsapp.md` (ordem igual a documentacao da API)

## Priorizacao por Sprint

## Sprint 1 (MVP obrigatorio)
- [ ] Definir arquitetura/contratos do provider NotificaMe.
- [ ] Criar provider `notificame` em `Channel::Whatsapp`.
- [ ] Criar configuracao de inbox/canal no dashboard.
- [ ] Entregar envio de texto.
- [ ] Entregar recebimento por webhook (texto).
- [ ] Entregar atualizacao de status de mensagem (minimo: sent/failed).

## Sprint 2 (MVP obrigatorio)
- [ ] Entregar envio de midia: audio, documento, imagem e video.
- [ ] Entregar reply com `in_reply_to_external_id`.
- [ ] Entregar recebimento de midia por webhook.
- [ ] Entregar interativos com botoes e listas.
- [ ] Entregar validacao fim a fim em staging (fluxo de inbox e conversa).

## Sprint 3 (Go-live + Pos-go-live prioritario)
- [ ] Entregar interativo CTA/link (se contrato estiver estavel).
- [ ] Entregar endpoint de saude do numero.
- [ ] Entregar bloqueio/desbloqueio e listagem de bloqueados.
- [ ] Entregar observabilidade minima (logs + alertas basicos).
- [ ] Executar rollout em ondas (piloto -> parcial -> geral).
- [ ] Executar plano de rollback testado.

## Classificacao de Escopo (MVP x Pos-go-live)

## MVP obrigatorio para publicar
- [ ] Enviar uma mensagem de texto.
- [ ] Enviar uma mensagem de audio.
- [ ] Enviar um arquivo (documentos, imagens, videos).
- [ ] Responder uma mensagem (marcar mensagem).
- [ ] Enviar mensagem interativa com botoes.
- [ ] Enviar mensagem interativa com listas.
- [ ] Veja a saude do numero (minimo operacional para suporte).

## MVP estendido (ideal antes do go-live geral)
- [ ] Enviar sticker.
- [ ] Enviar localizacao.
- [ ] Enviar mensagem interativa com link / CTA.
- [ ] Fazer o download de um arquivo criptografado.

## Pos-go-live
- [ ] Reagir a uma mensagem.
- [ ] Listar usuarios bloqueados.
- [ ] Bloquear usuario.
- [ ] Desbloquear usuario.
- [ ] Balao de digitando.

## Checklist Macro
- [ ] Fase 1 concluida
- [ ] Fase 2 concluida
- [ ] Fase 3 concluida
- [ ] Fase 4 concluida
- [ ] Fase 5 concluida
