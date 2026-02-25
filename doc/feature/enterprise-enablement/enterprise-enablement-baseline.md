# Baseline de Habilitação Enterprise — Self-hosted Lab

**Data:** 2026-02-25  
**Ambiente:** Self-hosted interno/lab (sem billing)

## 1. Pré-requisitos validados

✓ Enterprise folder presente: `/home/cesar/chatwoot/enterprise/`  
✓ `DISABLE_ENTERPRISE` não definido  
✓ `ChatwootApp.enterprise?` → `true`  
✓ `ChatwootApp.chatwoot_cloud?` → `false`  
✓ `ChatwootApp.self_hosted_enterprise?` → `false` (porque plano ainda é "community")

## 2. Configuração de instalação atual

```ruby
INSTALLATION_PRICING_PLAN: "community"
INSTALLATION_PRICING_PLAN_QUANTITY: 0
ACCOUNT_LEVEL_FEATURE_DEFAULTS: (array completo de features defaults)
```

## 3. Contas no sistema

### Account ID: 1
- **Nome:** Acme Inc
- **Feature flags (bitmask):** `1513539483037335511`
- **Features atualmente habilitadas:**
  - inbound_emails
  - channel_email
  - channel_facebook
  - ip_lookup
  - email_continuity_on_api_channel
  - help_center
  - agent_bots
  - macros
  - agent_management
  - team_management
  - inbox_management
  - labels
  - custom_attributes
  - automations
  - canned_responses
  - integrations
  - voice_recorder
  - channel_website
  - campaigns
  - reports
  - crm
  - auto_resolve_conversations
  - custom_reply_email
  - custom_reply_domain
  - linear_integration
  - chatwoot_v4
  - channel_instagram
  - crm_integration
  - notion_integration
  - whatsapp_campaign
  - quoted_email_reply
  - channel_tiktok
  - captain_tasks

- **Features premium NÃO habilitadas:**
  - audit_logs
  - disable_branding
  - saml
  - sla
  - custom_roles
  - csat_review_notes
  - conversation_required_attributes
  - advanced_assignment
  - captain_integration
  - captain_integration_v2
  - channel_voice

- **Plan (custom_attributes):** (vazio)
- **Limits:** `{}`
- **audio_transcriptions:** `true`

## 4. Features Enterprise a habilitar (conforme billing service)

Business plan features:
- custom_roles
- sla

Enterprise plan features:
- audit_logs
- disable_branding
- saml
- csat_review_notes
- conversation_required_attributes
- advanced_assignment

## 5. Rollback procedure

Para reverter todas as mudanças:

```ruby
# 1. Restaurar plano
InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'community')

# 2. Restaurar feature flags para Account ID 1
Account.find(1).update!(feature_flags: 1513539483037335511)

# 3. Reiniciar Rails para aplicar configs
# (restart Overmind/Rails server)
```

## 6. Problemas conhecidos a corrigir

1. **404 no endpoint limits**: Frontend chama `GET /enterprise/api/v1/accounts/:id/limits` que retorna 404 em self-hosted porque `check_cloud_env` exige `chatwoot_cloud?`
2. **Console warning**: Modal.vue `onClose` prop deprecation (já corrigido anteriormente)

---

**Nota**: Este documento serve como snapshot para rollback. Qualquer mudança deve ser documentada aqui junto com seu timestamp.
