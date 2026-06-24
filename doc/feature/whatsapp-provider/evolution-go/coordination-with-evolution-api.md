# Coordenação — Evolution Go vs Evolution API (Node)

Como o provider **`evolution_go`** se relaciona com **`evolution`** já em implementação no fork.

**Estado Node (jun/2026):** Fase 0–3 em `custom/app/services/custom/whatsapp/evolution/` — ver [../evolution-api/tasks.md](../evolution-api/tasks.md).

**Estado Go:** somente documentação — ver [status.md](./status.md).

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
| Componente wizard Vue raiz | Campos `global_api_key` + token Go distintos |
| Fixtures | Pastas separadas |

---

## O que REUSAR no frontend (composable)

Extrair de `EvolutionWhatsapp.vue` um composable **`useGatewayWhatsappWizard`**:

| Lógica compartilhada | Evolution Node | Evolution Go |
|---------------------|----------------|--------------|
| Polling QR / status | ✅ | ✅ |
| ActionCable connection | canal diferente | `evolution_go:connection:{id}` |
| Stepper 3 passos | ✅ | ✅ |
| Health check `server/ok` | opcional | **recomendado** Step 1 |
| REST direto no browser | ❌ | ❌ — sempre via backend |

Componentes finos: `EvolutionGoWhatsapp.vue` importa o composable + campos específicos (`global_api_key`, modo instância existente).

Detalhe: [frontend-wizard-spec.md § Composable](./frontend-wizard-spec.md#composable-compartilhado).

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

> **⚠️ ALERTA CRÍTICO — prepend collision:** O prepend evolution Node (`Custom::Webhooks::WhatsappEventsJob`) detecta `evolution_envelope?` verificando `params[:event].present? && params[:instance_name ou :instance].present?`. Evolution Go tem **o mesmo formato de envelope**, então **sem isolamento o prepend Node consumiria e descartaria silenciosamente os eventos Go**, nunca chamando `super`.

**Solução (ADR §27):**

1. `EvolutionGoController#sanitized_job_payload` injeta `evolution_go_instance_name:` (não `instance_name:`) e remove o campo `instance` do payload bruto.
2. O prepend evolution_go detecta por `params[:evolution_go_instance_name].present?` — campo injetado exclusivamente pelo controller Go.
3. O prepend evolution node deve usar `return super(params)` (não `return`) quando o canal não é encontrado — tarefa I0.7 em [tasks.md](./tasks.md).

```ruby
# EvolutionGoController (correto)
def sanitized_job_payload
  raw = params.to_unsafe_hash.except('controller', 'action', 'instance_name', 'token')
  raw.delete('instance')   # remove campo ambíguo
  raw
end

def process_payload
  Webhooks::WhatsappEventsJob.perform_later(
    sanitized_job_payload.merge(
      evolution_go_instance_name: params[:instance_name],  # chave distinta!
      channel_id: @channel.id
    )
  )
  head :ok
end

# Prepend evolution_go
def evolution_go_envelope?(params)
  params[:evolution_go_instance_name].present?
end
```

**⚠️ NÃO usar** `params[:event].in?(%w[MESSAGE ...]) && params[:instance].present?` como critério — ambíguo com evolution node. Ver [decisions.md §27](./decisions.md).

---

## Frontend `Whatsapp.vue`

Dois cards distintos:

| Card | Provider |
|------|----------|
| Evolution API | `evolution` |
| Evolution Go | `evolution_go` |

Componentes separados: `EvolutionWhatsapp.vue` vs `EvolutionGoWhatsapp.vue` — lógica comum em `useGatewayWhatsappWizard` (ver acima).

---

## Ordem de implementação sugerida

```
I0 Fase 0 (registry) → I1 Fase 1 MVP
                              │
                              └── E1 E2E (paralelo) — fixtures reais
```

1. **Fase 0** — [tasks.md](./tasks.md)
2. **Node** E2E pendente — não bloqueia Go Fase 0
3. **Go Fase 1** — contratos Postman/ADRs; fixtures refinadas no E2E

Implementar prepend `WhatsappEventsJob` branch Go **com specs** — evita regressão no Node.

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
| Status doc Go | [status.md](./status.md) |
