# Status — Z-API (`zapi`)

**Última revisão:** 23/jun/2026 — [documentation-review.md](./documentation-review.md)

## Resumo

| Área | Estado |
|------|--------|
| Collection Postman mapeada | ✅ fork + oficial identificadas |
| Contratos REST documentados (MVP) | ✅ `api-reference.md` |
| Payloads webhook documentados | ✅ oficiais + [documentation-review.md](./documentation-review.md) |
| Plano de implementação | ✅ `implementation-plan.md` |
| Código `custom/` | ❌ |
| `PROVIDERS` whitelist | ❌ (`zapi` pendente) |
| Registry | ❌ |
| Fixtures reais | ❌ |
| Validação E2E | ❌ |

## Bloqueios conhecidos

| # | Bloqueio | Impacto |
|---|----------|---------|
| 1 | Contrato multi-provider ainda em estabilização (`evolution` piloto) | Z-API entra após padrão estável |
| 2 | ~~4–7 URLs de webhook~~ | **Fechado:** rota única multiplexada — ver [decisions.md §2](./decisions.md) |
| 3 | Mídia com URL temporária (30 dias) | Download imediato no inbound obrigatório |
| 4 | Sem templates Meta | Paridade limitada vs Cloud API |
| 5 | API Partners opcional | Wizard pode exigir credenciais manuais no MVP |

## Próximos passos documentação

1. ~~Validar payloads oficiais~~ — feito via developer.z-api.io
2. ~~Confirmar `PUT .../update-every-webhooks`~~ — confirmado doc oficial (ausente Postman)
3. Executar [validation-checklist.md](./validation-checklist.md) com instância real
4. Salvar fixtures em `spec/fixtures/zapi/`
5. Escrever `troubleshooting.md` após primeiro piloto

## Dependências do fork

Antes de codificar:

- [ ] `evolution` estável em produção piloto
- [ ] `MessagingProvider::Registry` suporta terceiro provider sem regressão
- [ ] Padrão de `source_id` unificado (`messageId` Z-API → `Message#source_id`)
