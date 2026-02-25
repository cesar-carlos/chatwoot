# Estratégia de Habilitação Enterprise — Self-hosted Lab

**Data:** 2026-02-25  
**Objetivo:** Habilitar recursos Enterprise em ambiente self-hosted sem billing

## 1. Estratégia implementada

### 1.1. Configuração global (INSTALLATION_PRICING_PLAN)

```ruby
InstallationConfig.find_or_create_by(name: 'INSTALLATION_PRICING_PLAN') do |config|
  config.value = 'enterprise'
end
```

**Efeito:**
- `ChatwootApp.self_hosted_enterprise?` → `true`
- `ChatwootHub.pricing_plan` → `'enterprise'`
- UI/fluxos globais tratam instalação como Enterprise

### 1.2. Habilitação de features por conta

Features habilitadas para Account ID 1 (Acme Inc):

**Business plan features:**
- `sla` — Service Level Agreements
- `custom_roles` — Papéis customizados
- `csat_review_notes` — Notas de revisão CSAT
- `conversation_required_attributes` — Atributos obrigatórios na resolução
- `advanced_assignment` — Atribuição avançada

**Enterprise plan features:**
- `audit_logs` — Logs de auditoria
- `disable_branding` — Remover branding Chatwoot
- `saml` — Autenticação SAML SSO

### 1.3. Como habilitar para novas contas

```ruby
# Para habilitar todas as features Enterprise em uma conta:
account = Account.find(ID)

business_features = %w[sla custom_roles csat_review_notes conversation_required_attributes advanced_assignment]
enterprise_features = %w[audit_logs disable_branding saml]

account.enable_features(*(business_features + enterprise_features))
account.save!
```

### 1.4. Verificação

```ruby
# Verificar features habilitadas:
account = Account.find(ID)
account.feature_enabled?(:sla)          # => true
account.feature_enabled?(:custom_roles) # => true
account.feature_enabled?(:audit_logs)   # => true
```

## 2. Features que requerem configuração adicional

Algumas features Enterprise precisam de configuração além da habilitação:

### 2.1. SAML (`saml`)
- Requer configuração de IdP (Identity Provider)
- Configurar em: Settings → Security → SAML
- Necessário: `SAML_ISSUER_URL`, `SAML_CERT`, `SAML_ACS_URL`

### 2.2. SLA (`sla`)
- Requer criação de políticas SLA
- Configurar em: Settings → SLA
- Definir tempos de resposta e resolução por inbox/prioridade

### 2.3. Custom Roles (`custom_roles`)
- Requer criação de papéis customizados
- Configurar em: Settings → Teams & Agents → Roles
- Definir permissões específicas por papel

### 2.4. Audit Logs (`audit_logs`)
- Habilitado automaticamente, logs começam a ser registrados
- Visualizar em: Settings → Audit Logs

### 2.5. Disable Branding (`disable_branding`)
- Remove branding Chatwoot da UI
- Efeito imediato após habilitação

## 3. Rollback

Para reverter a habilitação Enterprise:

```ruby
# 1. Desabilitar features por conta
account = Account.find(1)
features_to_disable = %w[sla custom_roles csat_review_notes conversation_required_attributes 
                         advanced_assignment audit_logs disable_branding saml]
account.disable_features(*features_to_disable)
account.save!

# 2. Restaurar plano para community
InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'community')

# 3. Reiniciar Rails
# (restart Overmind/Rails server)
```

## 4. Próximos passos

1. ✓ Plano configurado como Enterprise
2. ✓ Features habilitadas para Account ID 1
3. ⏳ Corrigir 404 do endpoint `/enterprise/api/v1/accounts/:id/limits`
4. ⏳ Validar funcionalidades Enterprise na UI
5. ⏳ Testar permissões e comportamento por feature
