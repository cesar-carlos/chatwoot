# Revisão da documentação — Z-API (`zapi`)

**Data:** 23/jun/2026  
**Escopo:** 16 arquivos em `z-api/` + docs pai que citam Z-API  
**Fontes:** Postman MCP (fork `9985534-…`), developer.z-api.io/llms.txt, código `custom/` Evolution implementado

---

## Veredito executivo

| Dimensão | Nota | Comentário |
|----------|------|------------|
| Cobertura vs Postman | **A** | 15 pastas mapeadas; MVP endpoints confirmados |
| Cobertura vs doc oficial | **B+** | Payloads webhook confirmados; bulk webhook só na doc web |
| Alinhamento fork Evolution | **B** | Havia divergência `webhook_secret` vs `webhook_token` — **corrigido nesta revisão** |
| Prontidão para codificar Fase 0 | **B+** | Falta E2E + fixtures; spec-design ajustado ao padrão job real |
| Completude vs evolution-go | **B** | Faltam `troubleshooting.md`, `coordination-*.md`, script sync |

**Conclusão:** documentação de **planejamento está madura** para iniciar Fase 0 após piloto `evolution` estável. **Não** substitui validação com instância real.

---

## Inventário por arquivo

| Arquivo | Papel | Estado | Observação |
|---------|-------|--------|------------|
| [README.md](./README.md) | Landing | ✅ | Índice completo |
| [status.md](./status.md) | Verdade operacional | ✅ | Distingue doc vs E2E |
| [documentation-links.md](./documentation-links.md) | Índice Postman | ✅ | Falta entrada `update-every-webhooks` explícita — corrigir |
| [postman-validation.md](./postman-validation.md) | Inventário collection | ✅ | ~180 requests; bulk webhook ausente na collection |
| [api-reference.md](./api-reference.md) | Contratos REST | ✅ | Path bulk confirmado via doc oficial |
| [webhook-events.md](./webhook-events.md) | Payloads | ✅ | Exemplos oficiais; `ConnectedCallback` completo |
| [decisions.md](./decisions.md) | ADRs | ✅ | 20 decisões; alinhado `webhook_token` |
| [spec-design.md](./spec-design.md) | Classes Ruby | ✅ | Alinhado padrão `EvolutionController` + job |
| [implementation-plan.md](./implementation-plan.md) | Fases | ✅ | Estimativa relativa sem número mágico |
| [provider-config-mapping.md](./provider-config-mapping.md) | JSONB | ✅ | `client_token` opcional se feature desativada |
| [feature-mapping.md](./feature-mapping.md) | Paridade | ✅ | Reply = `messageId` em `send-text` |
| [validation-checklist.md](./validation-checklist.md) | E2E | ⚠️ | Não executado — próximo passo operacional |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI | ✅ | Polling QR 10–20s (doc Z-API) |
| [business-rules-adaptation.md](./business-rules-adaptation.md) | Regras CW | ✅ | |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | Comparativo | ✅ | |
| [tasks.md](./tasks.md) | Backlog | ✅ | |

### Ausentes (vs evolution-go)

| Documento | Prioridade | Quando criar |
|-----------|------------|--------------|
| `troubleshooting.md` | Média | Após primeiro piloto |
| `coordination-with-evolution-api.md` | Baixa | Antes de codificar (1 página) |
| `sync-documentation-links.sh` | Baixa | Quando llms.txt mudar com frequência |
| `inbox-business-rules.md` | — | Coberto por `business-rules-adaptation.md` |

---

## Validações cruzadas (Postman + doc oficial)

### Confirmado ✅

| Item | Evidência |
|------|-----------|
| URL pattern `/instances/{id}/token/{token}/…` | Postman variáveis + todos requests |
| `Client-Token` header | Postman + security/client-token.md |
| `GET /status`, `/qr-code`, `/qr-code/image`, `/disconnect` | Postman Instance |
| `POST /send-text` → `messageId` | send-text.md + Postman |
| Reply = `messageId` opcional no **mesmo** `send-text` | Postman "Responder mensagem" → path `send-text` |
| Webhooks individuais `PUT /update-webhook-*` | Postman Webhooks (7 itens) |
| `PUT /update-every-webhooks` | doc oficial (ausente na collection Postman) |
| `ReceivedCallback`, `DeliveryCallback`, `MessageStatusCallback` | webhook examples oficial |
| `ConnectedCallback` com `phone`, `connected` | on-webhook-connected.md |
| `GET /phone-exists/{phone}` | Postman Contacts |
| Partners `POST /instances/integrator/on-demand` | Postman Partners |
| QR expira ~20s; polling 10–20s recomendado | instance/qrcode.md |

### Corrigido nesta revisão 🔧

| Problema | Era | Agora |
|----------|-----|-------|
| Nome campo webhook | `webhook_secret` | `webhook_token` (igual Evolution **implementado**) |
| Polling QR wizard | 3s | 10–20s + nota expiração 20s |
| `update-every-webhooks` | "path inferido" | `PUT …/update-every-webhooks` confirmado |
| Reply Fase 2 | endpoint separado implícito | `send-text` + `messageId` |
| `client_token` | sempre obrigatório | obrigatório **se** ativado na conta Z-API |
| `GET /me` | Fase 2 | Fase 1 (sync `phone_number`) |
| Estimativa esforço | "0.7× Evolution" | tabela qualitativa sem fator único |

### Ainda pendente ⚠️

| Item | Bloqueio | Ação |
|------|----------|------|
| Fixtures `spec/fixtures/zapi/` | Sem instância teste | validation-checklist E2E |
| `DisconnectedCallback` payload completo | Doc parcial | Capturar no E2E |
| Tipo exato `DisconnectedCallback` vs nome no JSON | Assumido | Validar no E2E |
| Interativos inbound (botões/listas) | Fora MVP | Fase 3+ |
| Chamadas Z-API | Postman tem Calls | Fora escopo; corrigir provider-comparison pai |

---

## Alinhamento com código fork (Evolution)

Padrões a **replicar** no `zapi`:

| Padrão Evolution | Aplicar em Z-API |
|------------------|----------------|
| `provider_config['webhook_token']` | ✅ |
| Controller passa `channel_id` + payload ao job | ✅ spec-design |
| `?token=` + `secure_compare` | ✅ decisions §3 |
| prepend job com early return `unless zapi_envelope?` | ✅ spec-design |
| `ConnectionService` + `Provisioner` separados | Considerar `Zapi::Provisioner` na Fase 1 |
| Normalizer classe dedicada | ✅ |

Diferenças **intencionais**:

| Evolution | Z-API |
|-----------|-------|
| Lookup `instance_name` | Lookup `instance_id` |
| Demux `event` (MESSAGES_UPSERT) | Demux `type` (ReceivedCallback) |
| Auth secundária `apikey` no body | Só `?token=` (sem apikey envelope) |
| `webhook/set` REST | `PUT update-webhook-*` |

---

## Docs pai — ações

| Arquivo | Ação |
|---------|------|
| [provider-comparison.md](../provider-comparison.md) | Link `z-api/`; 7 webhooks; Calls documentados |
| [gaps-and-blockers.md](../gaps-and-blockers.md) | OK — `zapi` pendente correto |
| [STATUS.md](../STATUS.md) | OK — doc ✅, código ❌ |
| [implementation-decision-tree.md](../implementation-decision-tree.md) | OK |

---

## Ordem recomendada antes do código

1. Executar [validation-checklist.md](./validation-checklist.md) (1 instância Z-API)
2. Salvar fixtures reais
3. Fase 0 infra (`PROVIDERS`, registry, rota stub)
4. Fase 1 com specs do normalizer usando fixtures oficiais + reais

---

## Histórico de revisões

| Data | Escopo |
|------|--------|
| 23/jun/2026 | Revisão completa inicial; correções `webhook_token`, QR polling, bulk webhook, reply |
