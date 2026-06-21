# Coordenação — Evolution Go vs Evolution API (Node)

Como o provider **`evolution_go`** se relaciona com **`evolution`** já em implementação no fork.

**Estado Node (jun/2026):** Fase 0–3 em `custom/app/services/custom/whatsapp/evolution/` — ver [../evolution-api/tasks.md](../evolution-api/tasks.md).

**Estado Go:** somente documentação — ver [implementation-readiness.md](./implementation-readiness.md).

---

## Decisão: providers separados

| | `evolution` | `evolution_go` |
|---|-------------|----------------|
| Provider key | `evolution` | `evolution_go` |
| Namespace Ruby | `Custom::Whatsapp::Evolution::*` | `Custom::Whatsapp::EvolutionGo::*` |
| Webhook route | `/webhooks/evolution/:instance_name` | `/webhooks/evolution_go/:instance_name` |
| ActionCable | `evolution:connection:{id}` | `evolution_go:connection:{id}` |
| ApiClient paths | Node Baileys API | Go `/send/text`, connect inline webhook |

**Nunca** compartilhar `ApiClient` ou `Normalizer` entre os dois.

---

## O que REUSAR (Fase 0)

| Componente | Reuso |
|------------|-------|
| `MessagingProvider::Registry` | ✅ Registrar entrada `evolution_go` |
| `# FORK:` `PROVIDERS` | ✅ Adicionar `'evolution_go'` na mesma linha |
| Prepend `Channel::Whatsapp#provider_service` | ✅ Já existe se Node implementado |
| Prepend `WhatsappEventsJob` | ✅ Adicionar branch `evolution_go_envelope?` |
| Prepend `MessageWindowService` | ✅ Incluir `evolution_go` na capability |
| Padrão `EvolutionController` webhook | ✅ Copiar estrutura para `EvolutionGoController` |

---

## O que NÃO compartilhar

| Componente | Motivo |
|------------|--------|
| `Evolution::ApiClient` | Paths e auth diferentes |
| `EvolutionNormalizer` | Evento `MESSAGES_UPSERT` vs `MESSAGE` |
| `ConnectionService` | `set_webhook` vs connect body |
| Wizard Vue | Campos `global_api_key` + token Go |
| Fixtures | Pastas separadas |

---

## PROVIDERS whitelist

**Fork atual (jun/2026):** só `evolution` está na constante — `evolution_go` entra no mesmo `# FORK:` quando implementar:

```ruby
# app/models/channel/whatsapp.rb — estado atual
PROVIDERS = %w[default whatsapp_cloud evolution].freeze

# alvo ao implementar Go:
PROVIDERS = %w[default whatsapp_cloud evolution evolution_go zapi notificame].freeze
```

---

## Registry

```ruby
# evolution já registrado — adicionar:
MessagingProvider::Registry.register('evolution_go') do |channel|
  Custom::Whatsapp::Providers::EvolutionGoService.new(whatsapp_channel: channel)
end
```

---

## Job prepend — detecção de envelope

```ruby
def evolution_go_envelope?(params)
  params['event'].in?(%w[MESSAGE CONNECTION QRCODE READ_RECEIPT SEND_MESSAGE]) &&
    params['instance'].present? &&
    !evolution_api_envelope?(params)  # não tem apikey body típico Node
end
```

**Cuidado:** não rotear envelope Node para normalizer Go — testar com fixtures de ambos.

---

## Frontend `Whatsapp.vue`

Dois cards distintos:

| Card | Provider |
|------|----------|
| Evolution API | `evolution` |
| Evolution Go | `evolution_go` |

Componentes separados: `EvolutionWhatsapp.vue` vs `EvolutionGoWhatsapp.vue`.

---

## Ordem de implementação sugerida

1. **Node** terminar E2E (webhook inbound + wizard QR) — [validation-checklist](../evolution-api/validation-checklist.md) §2–4
2. **Go** spike fixtures
3. **Go** Fase 1 reutilizando infra Fase 0 já validada pelo Node

Implementar Go **antes** do Node terminar E2E é possível, mas aumenta risco de regressão no prepend compartilhado.

---

## Operador com ambos os servidores

| Cenário | Configuração |
|---------|--------------|
| Inbox A → Evolution API Node | `base_url` = servidor Node, `provider: evolution` |
| Inbox B → Evolution Go | `base_url` = servidor Go, `provider: evolution_go` |
| Mesmo servidor físico | **Não suportado** — APIs diferentes, portas diferentes |

---

## Documentação cruzada

| Dúvida | Documento |
|--------|-----------|
| Diferenças API | [differences-from-evolution-api.md](./differences-from-evolution-api.md) |
| Node implementado | [../evolution-api/README.md](../evolution-api/README.md) |
| Gaps doc Go | [gaps-and-improvements.md](./gaps-and-improvements.md) |
