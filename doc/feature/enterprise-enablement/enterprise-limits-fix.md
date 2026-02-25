# Correção: Endpoint `/limits` para Self-hosted Enterprise

**Data:** 2026-02-25  
**Problema:** Frontend chama `GET /enterprise/api/v1/accounts/:id/limits` mas o endpoint retorna 404 em self-hosted porque `check_cloud_env` só permite acesso em `chatwoot_cloud?`

## Solução implementada

### 1. Modificação no controller Enterprise

**Arquivo:** `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb`

#### 1.1. Alteração em `check_cloud_env`

```ruby
def check_cloud_env
  # FORK: Allow self-hosted Enterprise to access limits endpoint
  return if ChatwootApp.self_hosted_enterprise?

  render json: { error: 'Not found' }, status: :not_found unless ChatwootApp.chatwoot_cloud?
end
```

**Efeito:**
- Self-hosted Enterprise pode acessar os endpoints protegidos por `check_cloud_env`
- Cloud continua funcionando normalmente
- Community edition (não Enterprise) ainda recebe 404

#### 1.2. Alteração em `limits`

```ruby
def limits
  limits = if ChatwootApp.self_hosted_enterprise?
             # FORK: Self-hosted Enterprise gets unlimited usage (no billing)
             {
               'conversation' => {},
               'non_web_inboxes' => {},
               'agents' => {},
               'captain' => {}
             }
           elsif default_plan?(@account)
             {
               'conversation' => {
                 'allowed' => 500,
                 'consumed' => conversations_this_month(@account)
               },
               'non_web_inboxes' => {
                 'allowed' => 0,
                 'consumed' => non_web_inboxes(@account)
               },
               'agents' => {
                 'allowed' => 2,
                 'consumed' => agents(@account)
               }
             }
           else
             default_limits
           end

  render json: { id: @account.id, limits: limits }, status: :ok
end
```

**Efeito:**
- Self-hosted Enterprise retorna limites vazios (ilimitado) - sem billing, sem restrições
- Cloud continua retornando limites baseados no plano Stripe
- Frontend não precisa de mudanças - recebe resposta 200 com limites apropriados

## Resultado

### Antes
```
GET /enterprise/api/v1/accounts/1/limits
=> 404 Not Found
```

Console:
```
[Error] GET .../accounts/1/limits 404 (Not Found)
```

### Depois
```
GET /enterprise/api/v1/accounts/1/limits
=> 200 OK
{
  "id": 1,
  "limits": {
    "conversation": {},
    "non_web_inboxes": {},
    "agents": {},
    "captain": {}
  }
}
```

Console: sem erros

## Compatibilidade

✅ **Cloud (Chatwoot SaaS):** Sem mudanças, continua funcionando com billing  
✅ **Self-hosted Enterprise:** Agora funciona, retorna limites vazios (ilimitado)  
✅ **Self-hosted Community:** Continua recebendo 404 (comportamento esperado)  

## Marcadores FORK

Todas as mudanças foram marcadas com `# FORK:` para rastreamento em merges com upstream.

## Endpoints afetados

A mudança em `check_cloud_env` também permite acesso self-hosted Enterprise ao endpoint:
- `POST /enterprise/api/v1/accounts/:id/toggle_deletion`

Para este endpoint, o comportamento é apropriado - self-hosted Enterprise pode marcar contas para deleção.
