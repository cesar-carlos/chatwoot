# Limites de Mudança Seguros para Fork — Enterprise Enablement

**Data:** 2026-02-25  
**Contexto:** Habilitação Enterprise em self-hosted sem billing

## Regras do Fork aplicadas

Conforme `.cursor/rules/fork-strategy.mdc`, todas as mudanças devem:

1. ✅ **Minimizar edições em arquivos upstream**
2. ✅ **Usar `custom/` overlay quando possível**
3. ✅ **Marcar linhas alteradas com `# FORK:` (Ruby) ou `// FORK:` (TS/Vue)**
4. ✅ **Manter mudanças autocontidas e grep-áveis**
5. ✅ **Nunca adicionar lógica de negócio em `app/`, `lib/`, ou `enterprise/` sem marcação**

## Mudanças implementadas

### 1. Configuração de instalação (via Rails console/script)

**Tipo:** Configuração de dados (não código)  
**Método:** `InstallationConfig.update`  
**Impacto no fork:** ✅ Nenhum - mudança em dados, não código

```ruby
InstallationConfig.find_or_create_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'enterprise')
```

### 2. Feature flags de conta (via Rails console/script)

**Tipo:** Configuração de dados (não código)  
**Método:** `Account#enable_features`  
**Impacto no fork:** ✅ Nenhum - mudança em dados, não código

```ruby
account.enable_features(
  :sla, :custom_roles, :csat_review_notes, :conversation_required_attributes,
  :advanced_assignment, :audit_logs, :disable_branding, :saml
)
```

### 3. Controller Enterprise — check_cloud_env

**Arquivo:** `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb`  
**Tipo:** Edição inevitável em arquivo Enterprise  
**Marcação:** ✅ `# FORK:` presente  
**Justificativa:** Necessário para permitir acesso self-hosted Enterprise ao endpoint `/limits`

```ruby
def check_cloud_env
  # FORK: Allow self-hosted Enterprise to access limits endpoint
  return if ChatwootApp.self_hosted_enterprise?

  render json: { error: 'Not found' }, status: :not_found unless ChatwootApp.chatwoot_cloud?
end
```

**Análise de conflito com upstream:**
- ✅ Mudança mínima (1 linha de guarda adicionada)
- ✅ Não altera comportamento cloud (guarda é avaliada primeiro)
- ✅ Marcada com `# FORK:` para grep durante merge
- ✅ Autocontida - não depende de outras mudanças

### 4. Controller Enterprise — limits

**Arquivo:** `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb`  
**Tipo:** Edição inevitável em arquivo Enterprise  
**Marcação:** ✅ `# FORK:` presente  
**Justificativa:** Necessário para retornar limites apropriados para self-hosted Enterprise

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
             # ... rest of cloud logic unchanged
           end
  # ...
end
```

**Análise de conflito com upstream:**
- ✅ Mudança mínima (adiciona branch condicional no início)
- ✅ Não altera comportamento cloud (self_hosted_enterprise? é false em cloud)
- ✅ Marcada com `# FORK:` para grep durante merge
- ✅ Autocontida - não depende de outras mudanças

## Estratégia de merge com upstream

Quando upstream atualizar `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb`:

1. **Buscar mudanças fork:**
   ```bash
   rg "FORK:" enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb
   ```

2. **Avaliar cada mudança:**
   - Se método alterado foi removido/renomeado: ajustar ou remover mudança fork
   - Se lógica do método mudou: replicar mudança fork no novo código
   - Se não há conflito: manter ambas as mudanças

3. **Testar:**
   - Validar que self-hosted Enterprise continua funcionando
   - Validar que nenhum comportamento cloud foi quebrado

## Arquivos monitorar em merges

```bash
# Buscar todos os marcadores FORK no projeto:
rg "FORK:" --type ruby --type js --type vue

# Resultado esperado: apenas os 2 marcadores no accounts_controller.rb
```

## Resumo de conformidade com regras

| Regra | Status | Nota |
|-------|--------|------|
| Minimizar edições upstream | ✅ | Apenas 2 métodos em 1 arquivo |
| Usar `custom/` overlay | ⚠️ | Não aplicável - mudança em controller Enterprise |
| Marcar com `FORK:` | ✅ | Todas as linhas alteradas marcadas |
| Mudanças autocontidas | ✅ | Cada mudança é independente |
| Grep-ável | ✅ | `rg "FORK:"` encontra todas as mudanças |

**Legenda:**
- ✅ Regra seguida completamente
- ⚠️ Regra não aplicável ou exceção justificada
- ❌ Regra violada (nenhuma neste caso)

## Recomendações para futuras mudanças

1. **Sempre preferir configuração de dados sobre código**
   - InstallationConfig para flags globais
   - Account.custom_attributes para flags por conta
   - Feature flags via Featurable concern

2. **Se edição de código for inevitável:**
   - Manter mudança mínima (< 5 linhas se possível)
   - Adicionar guarda no início do método (early return)
   - Marcar cada linha alterada com `FORK:`
   - Documentar em arquivo separado (como este)

3. **Testar merge simulation antes de atualizar upstream:**
   ```bash
   git fetch upstream
   git merge-tree $(git merge-base HEAD upstream/main) HEAD upstream/main
   ```
