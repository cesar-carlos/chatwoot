# Fase 2 - MVP Canal e Mensagens Base

## Objetivo
- Entregar nova inbox WhatsApp via NotificaMe com recursos essenciais de operacao.

## Prioridade
- Sprint alvo: Sprint 1 e Sprint 2
- Classificacao: MVP obrigatorio

## TODOs
- [ ] Implementar provider NotificaMe para envio de mensagem de texto.
- [ ] Implementar envio de audio.
- [ ] Implementar envio de arquivo (documento, imagem, video).
- [ ] Implementar envio de sticker (ou fallback definido na Fase 1).
- [ ] Implementar envio de localizacao (se suportado no provider).
- [ ] Implementar reply com `in_reply_to_external_id` no envio.
- [ ] Implementar ingestao de webhook para mensagens recebidas (texto e midia).
- [ ] Implementar atualizacao de status de mensagem (sent/delivered/read/failed conforme suporte).
- [ ] Implementar tela de configuracao de inbox no dashboard (credenciais e validacao).
- [ ] Permitir criacao de nova caixa de entrada via fluxo de canais.

## Criterio de Conclusao
- [ ] Inbox NotificaMe criada e operacional em ambiente de desenvolvimento.
- [ ] Fluxo fim a fim: enviar e receber texto e midia.
- [ ] Erros principais retornam feedback legivel no Chatwoot.
