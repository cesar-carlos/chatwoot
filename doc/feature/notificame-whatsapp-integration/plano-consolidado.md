# Integracao NotificaMe WhatsApp - Plano Consolidado

## Objetivo
- Centralizar o plano em uma unica fonte de verdade para execucao.
- Reduzir sobreposicao entre arquivos de fase e etapas.
- Garantir sequencia pratica: arquitetura -> MVP -> avancados -> operacao -> go-live.

## Referencia Obrigatoria
- Documentacao oficial da API NotificaMe WhatsApp: `https://app.notificame.com.br/docs/#/api?id=-whatsapp`

## Regras de Execucao
- [ ] Antes de cada item, validar endpoint, metodo, auth, payload e response na documentacao oficial.
- [ ] Registrar mapeamento de erros do provider para erros legiveis no Chatwoot.
- [ ] Validar observabilidade minima (logs e status operacional) para cada bloco entregue.
- [ ] Entregar em lotes pequenos com validacao fim a fim por etapa.

## Sequencia Consolidada (Sprint x Fase)

## Sprint 1 - Fundacao + MVP inicial
- [ ] Fase 1: arquitetura e contratos aprovados.
- [ ] Criar provider `notificame` em `Channel::Whatsapp`.
- [ ] Criar configuracao de inbox no dashboard (credenciais e validacao).
- [ ] Entregar texto (envio e recebimento via webhook).
- [ ] Entregar status minimo de mensagem (sent/failed).

## Sprint 2 - MVP obrigatorio
- [ ] Entregar audio.
- [ ] Entregar arquivo (documentos, imagens, videos).
- [ ] Entregar reply (`in_reply_to_external_id`).
- [ ] Entregar interativos com botoes e listas.
- [ ] Validar staging fim a fim (criar inbox, enviar, receber, status, erros).

## Sprint 3 - Go-live + extensoes
- [ ] Entregar saude do numero.
- [ ] Entregar bloqueados (listar, bloquear, desbloquear).
- [ ] Entregar CTA/link interativo (se contrato estiver estavel).
- [ ] Executar rollout em ondas e plano de rollback.

## Pos-go-live
- [ ] Reacao a mensagem.
- [ ] Balao de digitando.
- [ ] Download de arquivo criptografado (se pendente no go-live).
- [ ] Hardening de observabilidade e carga.

## Backlog Funcional Consolidado (ordem da API)

## 1) Enviar uma mensagem de texto
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 2) Enviar uma mensagem de audio
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 3) Enviar um sticker
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 4) Enviar um arquivo (documentos, imagens, videos)
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 5) Enviar localizacao
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 6) Enviar mensagem interativa com botoes
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 7) Enviar mensagem interativa com listas
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 8) Enviar mensagem interativa com link / CTA
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 9) Reagir a uma mensagem
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 10) Responder uma mensagem (marcar mensagem)
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 11) Fazer o download de um arquivo criptografado
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 12) Veja a saude do numero
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 13) Listar usuarios bloqueados
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 14) Bloquear usuario
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 15) Desbloquear usuario
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## 16) Balao de digitando
- Endpoint:
- Metodo:
- Auth:
- Payload exemplo:
- Response exemplo:
- [ ] Implementado
- [ ] Validado fim a fim

## Criterios de Go-live
- [ ] Todos os itens MVP obrigatorio concluido.
- [ ] Health check funcional por inbox.
- [ ] Teste de regressao em canais WhatsApp existentes concluido.
- [ ] Runbook e rollback testados.
- [ ] Piloto sem incidente critico por janela definida.

## Status Consolidado
- [ ] Fase 1 concluida
- [ ] Fase 2 concluida
- [ ] Fase 3 concluida
- [ ] Fase 4 concluida
- [ ] Fase 5 concluida
