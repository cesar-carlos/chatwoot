# Coordenação — Z-API vs Evolution no mesmo fork

Como `zapi` e `evolution` coexistem sem colisão. Irmão: [../evolution-go/coordination-with-evolution-api.md](../evolution-go/coordination-with-evolution-api.md).

---

## Regra de ouro

**Um inbox = um provider.** Nunca compartilhar instância Z-API com Evolution ou misturar adapters.

---

## Coexistência permitida

| Inbox A | Inbox B | OK? |
|---------|---------|-----|
| `provider: 'evolution'` | `provider: 'zapi'` | ✅ mesmo account Chatwoot |
| `provider: 'zapi'` | `provider: 'zapi'` | ✅ instâncias Z-API diferentes |
| Mesmo `phone_number` | dois providers | ❌ unique em `Channel::Whatsapp` |

---

## Rotas webhook

| Provider | Rota | Lookup |
|----------|------|--------|
| `evolution` | `POST /webhooks/evolution/:instance_name` | `instance_name` |
| `zapi` | `POST /webhooks/zapi/:instance_id` | `instance_id` |

Sem colisão de path.

---

## Registry

```ruby
# Futuro — após implementação
PROVIDERS = %w[default whatsapp_cloud evolution evolution_go zapi notificame].freeze
```

Registrar cada provider separadamente em `messaging_provider_registry.rb`.

---

## Código compartilhado (OK)

| Componente | Compartilhar? |
|------------|---------------|
| `MessagingProvider::Registry` | ✅ |
| prepend `Channel::Whatsapp` | ✅ |
| prepend `MessageWindowService` | ✅ |
| prepend `WhatsappEventsJob` | ✅ com branches por provider |
| Wizard composable base | ✅ UI separada por provider |
| `EvolutionService` / `ZapiService` | ❌ nunca |
| Normalizers | ❌ nunca |

---

## Ordem de implementação sugerida

1. `evolution` estável em produção
2. `evolution_go` **ou** `zapi` (não ambos em paralelo)
3. Z-API se operador prefere SaaS sem self-host
