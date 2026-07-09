# Coordenação — Evolution Go vs Evolution API (Node)

Como o provider **`evolution_go`** se relaciona com **`evolution`** no fork.

**Estado Node:** implementado em `custom/app/services/custom/whatsapp/evolution/` — ver [../evolution-api/README.md](../evolution-api/README.md).

**Estado Go:** implementado em `custom/app/services/custom/whatsapp/evolution_go/` — ver [status.md](./status.md). E2E com servidor real pendente.

---

## Decisão: providers separados

| | `evolution` | `evolution_go` |
|---|-------------|----------------|
| Provider key | `evolution` | `evolution_go` |
| Namespace Ruby | `Custom::Whatsapp::Evolution::*` | `Custom::Whatsapp::EvolutionGo::*` |
| Webhook route | `/webhooks/evolution/:instance_name` | `/webhooks/evolution_go/:instance_name` |
| ActionCable | `evolution:connection:{id}` | `evolution_go:connection:{id}` |
| ApiClient paths | Node Baileys API | Go `/send/text`, connect inline webhook |
| Wizard Vue | `Evolution.vue` | `EvolutionGo.vue` |

**Nunca** compartilhar `ApiClient` ou `Normalizer` entre os dois.

---

## O que foi reutilizado (Fase 0)

| Componente | Situação |
|------------|----------|
| `MessagingProvider::Registry` | ✅ `evolution_go` registrado (posicional) |
| `# FORK:` `PROVIDERS` | ✅ `%w[default whatsapp_cloud evolution evolution_go]` |
| Prepend `Channel::Whatsapp#provider_service` | ✅ gateway-aware |
| Prepend `WhatsappEventsJob` | ✅ branch `evolution_go_envelope?` |
| Prepend `MessageWindowService` | ✅ capability `unlimited_session` |
| Padrão webhook controller | ✅ `EvolutionGoController` |
| Grupos / mutex | ✅ reuso pontual de `Evolution::GroupContactService`, `MessageMutex`, etc. |

---

## O que NÃO é compartilhado

| Componente | Motivo |
|------------|--------|
| `Evolution::ApiClient` | Paths e auth diferentes |
| `EvolutionNormalizer` | Evento `MESSAGES_UPSERT` vs `MESSAGE` |
| `ConnectionService` | `set_webhook` vs connect body |
| Wizard Vue raiz | Campos `global_api_key` + token Go distintos |
| Fixtures | Pastas `spec/fixtures/evolution/` vs `evolution_go/` |

---

## Frontend — o que existe vs o que foi planejado

| Planejado (ADR antigo) | Implementado |
|------------------------|--------------|
| `EvolutionGoWhatsapp.vue` | `EvolutionGo.vue` |
| `useGatewayWhatsappWizard.js` compartilhado | **Não extraído** — composables dedicados sob `composables/evolution_go/` |
| Gates `isEvolutionGoWhatsAppChannel` | `isGatewayWhatsAppProvider` / `isGatewayWhatsAppInbox` em `lib/whatsapp/gatewayProviders.js` (+ helpers por provider nas settings) |

Composables Go:

| Arquivo | Papel |
|---------|-------|
| `useEvolutionGoQrSession.js` | QR modal + polling |
| `useEvolutionGoHealthConnection.js` | reconnect / logout / status |
| `useEvolutionGoImportStatus.js` | polling import |
| `evolutionGoCableRegistry.js` | ActionCable |

Extrair um `useGatewayWhatsappWizard` genérico permanece **opcional** (DRY futuro) — não bloqueia operação.

---

## PROVIDERS whitelist

**Código atual:**

```ruby
# app/models/channel/whatsapp.rb
PROVIDERS = %w[default whatsapp_cloud evolution evolution_go].freeze
```

---

## Registry

**Código atual** (`custom/config/initializers/messaging_provider_registry.rb`):

```ruby
MessagingProvider::Registry.register(
  'evolution_go',
  Custom::Whatsapp::Providers::EvolutionGoService
)
```

Formato **posicional** (igual ao Node) — não usar bloco `|channel|`.

---

## Job prepend — detecção de envelope

> **⚠️ ALERTA CRÍTICO — prepend collision:** O prepend evolution Node detecta `evolution_envelope?` via `params[:event]` + `instance_name`/`instance`. Evolution Go tem o mesmo formato de envelope — **sem isolamento o prepend Node consumiria e descartaria eventos Go**.

**Solução implementada (ADR §27):**

1. `EvolutionGoController#sanitized_job_payload` remove `instance` e o job recebe `evolution_go_instance_name:` (não `instance_name:`).
2. Prepend Go: `params[:evolution_go_instance_name].present?`.
3. Prepend Node: `return super(params)` quando canal não encontrado.

```ruby
# EvolutionGoController (implementado)
def sanitized_job_payload
  payload = params.to_unsafe_hash.except('controller', 'action', 'instance_name', 'token')
  payload.delete('instance')
  payload
end

# process_payload mergeia:
#   evolution_go_instance_name: params[:instance_name], channel_id: @channel.id

def evolution_go_envelope?(params)
  params[:evolution_go_instance_name].present?
end
```

**⚠️ NÃO usar** `params[:event]` + `params[:instance]` como critério Go — ambíguo com Node. Ver [decisions.md §27](./decisions.md).

---

## Frontend `Whatsapp.vue`

Dois cards distintos:

| Card | Provider | Componente |
|------|----------|------------|
| Evolution API | `evolution` | `Evolution.vue` |
| Evolution Go | `evolution_go` | `EvolutionGo.vue` |

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
| Status Go | [status.md](./status.md) |
