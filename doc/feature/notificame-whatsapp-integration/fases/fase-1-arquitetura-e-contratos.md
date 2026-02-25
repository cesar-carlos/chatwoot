# Fase 1 - Arquitetura e Contratos

## Objetivo
- Definir arquitetura de provider NotificaMe no fluxo WhatsApp existente.
- Mapear contratos de envio, webhook e autenticacao.

## Prioridade
- Sprint alvo: Sprint 1
- Classificacao: MVP obrigatorio

## TODOs
- [ ] Definir nome e chave do provider (`notificame`) em `Channel::Whatsapp`.
- [ ] Mapear credenciais necessarias (token, instancia, endpoint base, headers).
- [ ] Especificar formato de payload para: texto, midia, interativos, reply e reacao.
- [ ] Especificar contrato de webhook para mensagens recebidas, status e eventos de sistema.
- [ ] Definir estrategia de idempotencia/deduplicacao para webhooks.
- [ ] Definir estrategia de normalizacao de numero (E.164) no provider.
- [ ] Definir matriz de compatibilidade entre recursos NotificaMe e tipos internos do Chatwoot.

## Criterio de Conclusao
- [ ] Documento de contratos aprovado (envio + recebimento + erros).
- [ ] Lista de gaps tecnicos priorizada para Fase 2 e Fase 3.
