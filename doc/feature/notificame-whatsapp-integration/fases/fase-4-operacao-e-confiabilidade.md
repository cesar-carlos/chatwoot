# Fase 4 - Operacao e Confiabilidade

## Objetivo
- Cobrir observabilidade, controles operacionais e robustez de producao.

## Prioridade
- Sprint alvo: Sprint 3
- Classificacao: Pos-go-live prioritario

## TODOs
- [ ] Implementar endpoint/acao para verificar saude do numero.
- [ ] Implementar listar usuarios bloqueados.
- [ ] Implementar bloquear usuario.
- [ ] Implementar desbloquear usuario.
- [ ] Implementar evento de "digitando" (typing indicator), conforme suporte do provider.
- [ ] Adicionar logs estruturados para erros de provider e webhooks.
- [ ] Definir alertas de falha de webhook e taxa de erro de envio.
- [ ] Revisar retries/backoff para chamadas HTTP externas.
- [ ] Validar comportamento com volume alto de mensagens (fila + deduplicacao).

## Criterio de Conclusao
- [ ] Saude e bloqueio/desbloqueio operando por inbox.
- [ ] Painel/logs suficientes para diagnosticar falhas sem acesso direto ao provider.
- [ ] Estabilidade comprovada em teste de carga controlado.
