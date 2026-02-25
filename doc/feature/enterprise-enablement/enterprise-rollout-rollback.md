# Procedimento de Rollout e Rollback — Enterprise Self-hosted

**Data:** 2026-02-25  
**Objetivo:** Definir sequência segura de rollout e procedimento de rollback em caso de problemas

## 1. Pré-requisitos para Rollout

Antes de iniciar o rollout, confirmar:

- [x] ✅ Baseline documentado em `doc/enterprise-enablement-baseline.md`
- [x] ✅ Estratégia de habilitação definida em `doc/enterprise-enablement-strategy.md`
- [x] ✅ Correção de 404 implementada em `doc/enterprise-limits-fix.md`
- [x] ✅ Mudanças fork-safe em `doc/enterprise-fork-boundaries.md`
- [x] ✅ Matriz de validação pronta em `doc/enterprise-validation-matrix.md`
- [ ] ⏳ Backup completo do banco de dados
- [ ] ⏳ Backup de `InstallationConfig` relevantes

## 2. Sequência de Rollout Gradual

### Fase 0: Preparação (ANTES de qualquer mudança)

```bash
# 1. Backup do banco de dados
cd /home/cesar/chatwoot
RAILS_ENV=development bundle exec rake db:dump
# Ou use pg_dump se preferir

# 2. Snapshot dos configs
bundle exec rails runner "
puts '=== InstallationConfig Snapshot ==='
InstallationConfig.where(name: ['INSTALLATION_PRICING_PLAN', 'ACCOUNT_LEVEL_FEATURE_DEFAULTS']).each do |c|
  puts \"#{c.name}: #{c.value.inspect}\"
end
puts ''
puts '=== Account Feature Flags ==='
Account.all.each do |a|
  puts \"Account #{a.id} (#{a.name}): feature_flags=#{a.feature_flags}\"
end
"

# Salvar output em arquivo para referência:
# ... > /tmp/pre-rollout-snapshot.txt
```

**✅ Checkpoint:** Confirmar que snapshot foi salvo antes de continuar.

### Fase 1: Configuração Global (baixo risco)

```bash
cd /home/cesar/chatwoot
eval "$(rbenv init -)"

bundle exec rails runner "
# Ativar modo Enterprise global
config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
config.value = 'enterprise'
config.save!

puts '✓ INSTALLATION_PRICING_PLAN = enterprise'
puts \"  Verificação: ChatwootApp.self_hosted_enterprise? = #{ChatwootApp.self_hosted_enterprise?}\"
"
```

**✅ Checkpoint:** 
- Verificar que `ChatwootApp.self_hosted_enterprise?` retorna `true`
- Nenhum erro no output

**⏱ Tempo estimado:** 30 segundos

### Fase 2: Conta Piloto (Account ID 1)

```bash
bundle exec rails runner "
account = Account.find(1)

# Habilitar features Enterprise
features_to_enable = %w[
  sla
  custom_roles
  csat_review_notes
  conversation_required_attributes
  advanced_assignment
  audit_logs
  disable_branding
  saml
]

puts \"Habilitando features Enterprise para Account \#{account.id} (\#{account.name})\"
account.enable_features(*features_to_enable)
account.save!

puts '✓ Features habilitadas:'
features_to_enable.each do |f|
  status = account.feature_enabled?(f) ? '✓' : '✗'
  puts \"  \#{status} \#{f}\"
end
"
```

**✅ Checkpoint:**
- Todas as features mostram ✓
- Nenhum erro no output

**⏱ Tempo estimado:** 1 minuto

### Fase 3: Restart e Validação Inicial

```bash
# Restart Rails server para aplicar mudanças
# Se usando Overmind:
cd /home/cesar/chatwoot
overmind restart rails

# Aguardar server subir (check http://localhost:3000)
sleep 10

# Testar endpoint limits
curl -s http://localhost:3000/enterprise/api/v1/accounts/1/limits \
  -H "api_access_token: YOUR_TOKEN" | jq .
```

**✅ Checkpoint:**
- Server reiniciou sem erros
- Endpoint `/limits` retorna 200 (não 404)
- Response contém `{ "id": 1, "limits": { ... } }`

**⏱ Tempo estimado:** 2-3 minutos

### Fase 4: Validação Funcional (Smoke Test)

Executar checklist do `doc/enterprise-validation-matrix.md` seção 6:

1. Login como admin
2. Abrir console do browser (F12)
3. Verificar que não há erro 404 de `/limits`
4. Navegar para Settings e confirmar novos menus:
   - SLA
   - Conversation Workflow
   - Audit Logs
   - Custom Roles
5. Testar criar 1 registro em feature crítica (ex: SLA policy)
6. Verificar branding removido
7. Testar conversa básica (não-regressão)

**✅ Checkpoint:**
- Todos os menus aparecem
- Ao menos 1 feature funciona (criar registro)
- Nenhuma regressão em funcionalidades OSS
- Console sem erros 404 críticos

**⏱ Tempo estimado:** 10-15 minutos

### Fase 5: Monitoramento (24h)

**Imediatamente após rollout:**
```bash
# Monitorar logs por 5-10 minutos
tail -f log/development.log | grep -i "error\|exception\|500"
```

**Durante primeiras 24h:**
- Verificar logs diariamente
- Monitorar uso das features Enterprise
- Coletar feedback de usuários piloto

**✅ Checkpoint (24h depois):**
- Sem erros críticos nos logs
- Features Enterprise sendo usadas
- Nenhuma reclamação de features OSS quebradas

### Fase 6: Expansão (Opcional - se houver mais contas)

Se houver múltiplas contas no sistema:

```bash
# Habilitar Enterprise para contas adicionais gradualmente
bundle exec rails runner "
# Exemplo: habilitar para Account ID 2, 3, etc.
[2, 3, 4].each do |account_id|
  account = Account.find(account_id)
  features = %w[sla custom_roles audit_logs ...]
  account.enable_features(*features)
  account.save!
  puts \"✓ Account \#{account_id} (\#{account.name}) habilitado\"
end
"
```

**Estratégia:**
- Dia 1: Account 1 (piloto)
- Dia 2-3: Accounts 2-3 (pequeno grupo)
- Dia 4-7: Restante das contas

## 3. Procedimento de Rollback

### Quando fazer rollback?

❌ **ROLLBACK IMEDIATO se:**
- Features OSS críticas quebradas (conversas, inboxes, agentes)
- Impossível fazer login
- Erro 500 generalizado
- Perda de dados

⚠️ **ROLLBACK OPCIONAL se:**
- Feature Enterprise específica com bug (pode desabilitar só essa feature)
- Performance degradada (investigar causa antes de rollback)
- Feedback negativo de UX (avaliar se é bug ou esperado)

### Rollback Completo

```bash
cd /home/cesar/chatwoot
eval "$(rbenv init -)"

# Etapa 1: Desabilitar features Enterprise por conta
bundle exec rails runner "
Account.all.each do |account|
  features_to_disable = %w[
    sla custom_roles csat_review_notes conversation_required_attributes
    advanced_assignment audit_logs disable_branding saml
  ]
  
  puts \"Desabilitando Enterprise features para Account \#{account.id}\"
  account.disable_features(*features_to_disable)
  account.save!
end
puts '✓ Features desabilitadas em todas as contas'
"

# Etapa 2: Restaurar plano para community
bundle exec rails runner "
config = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')
config.update!(value: 'community')
puts '✓ INSTALLATION_PRICING_PLAN restaurado para: community'
"

# Etapa 3: Reverter mudanças de código (se necessário)
git checkout HEAD -- enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb
git status

# Etapa 4: Restart Rails
overmind restart rails

# Etapa 5: Verificar rollback
bundle exec rails runner "
puts 'Verificação pós-rollback:'
puts \"  ChatwootApp.self_hosted_enterprise? = #{ChatwootApp.self_hosted_enterprise?}\"
puts \"  Account 1 features enabled: #{Account.find(1).enabled_features.keys.join(', ')}\"
"
```

**✅ Checkpoint pós-rollback:**
- `self_hosted_enterprise?` retorna `false`
- Features Enterprise não aparecem em contas
- Funcionalidades OSS funcionam normalmente

**⏱ Tempo de rollback:** 5-10 minutos

### Rollback Parcial (Feature Específica)

Se apenas uma feature específica está com problema:

```bash
# Desabilitar apenas uma feature
bundle exec rails runner "
Account.all.each do |account|
  account.disable_features('sla')  # Exemplo: desabilitar SLA
  account.save!
end
puts '✓ Feature SLA desabilitada'
"
```

### Rollback de Dados (Banco)

Se houve corrupção de dados (cenário extremo):

```bash
# Restaurar backup do banco
# ATENÇÃO: Isso apaga TODOS os dados criados após o backup!
RAILS_ENV=development bundle exec rake db:restore

# Ou com pg_restore
pg_restore -d chatwoot_development /path/to/backup.dump
```

⚠️ **ATENÇÃO:** Só usar em caso de corrupção crítica. Perda de dados desde o backup.

## 4. Comunicação durante Rollout

### Template de Comunicação (Início)

```
🚀 Rollout: Habilitação Enterprise Self-hosted

Status: EM PROGRESSO
Horário: [DATA/HORA]
Impacto esperado: Nenhum downtime, novas features disponíveis

Mudanças:
- Habilitação de features Enterprise (SLA, Custom Roles, Audit Logs, etc.)
- Correção de erro 404 no endpoint /limits

Timeline:
- [HH:MM] Início do rollout
- [HH:MM] Conta piloto habilitada
- [HH:MM] Validação funcional
- [HH:MM] Conclusão esperada

Contato para problemas: [SEU CONTATO]
```

### Template de Comunicação (Conclusão)

```
✅ Rollout Concluído: Enterprise Self-hosted

Status: SUCESSO
Horário conclusão: [DATA/HORA]

Resultados:
- ✓ Account 1 (piloto) com features Enterprise ativas
- ✓ Endpoint /limits funcionando (sem erro 404)
- ✓ Validação funcional aprovada
- ✓ Sem regressões detectadas

Próximos passos:
- Monitoramento contínuo por 24h
- Expansão para demais contas em [DATA]

Features disponíveis:
- SLA, Custom Roles, Audit Logs, Disable Branding, 
  SAML, CSAT Notes, Required Attributes, Advanced Assignment
```

### Template de Comunicação (Rollback)

```
⚠️ Rollback Executado: Enterprise Self-hosted

Status: REVERTIDO
Horário: [DATA/HORA]
Motivo: [DESCREVER PROBLEMA]

Ações realizadas:
- Features Enterprise desabilitadas
- Configuração restaurada para 'community'
- [Outras ações]

Estado atual: Sistema operacional normal em modo Community

Próximos passos:
- Análise da causa raiz
- Correção do problema
- Planejamento de novo rollout
```

## 5. Checklist Executivo (TL;DR)

### Pré-Rollout
- [ ] Backup do banco de dados
- [ ] Snapshot de configs salvos
- [ ] Matriz de validação revisada

### Rollout
- [ ] Fase 1: Configuração global (INSTALLATION_PRICING_PLAN)
- [ ] Fase 2: Habilitar features na conta piloto
- [ ] Fase 3: Restart e validar endpoint /limits
- [ ] Fase 4: Smoke test funcional (10-15 min)
- [ ] Fase 5: Monitorar por 24h

### Pós-Rollout (24h)
- [ ] Verificar logs sem erros críticos
- [ ] Confirmar uso de features Enterprise
- [ ] Coletar feedback de usuários

### Rollback (se necessário)
- [ ] Desabilitar features Enterprise
- [ ] Restaurar INSTALLATION_PRICING_PLAN = 'community'
- [ ] Reverter código (git checkout)
- [ ] Restart Rails
- [ ] Validar funcionalidades OSS

---

**Documento mantido por:** [Seu nome/equipe]  
**Última atualização:** 2026-02-25  
**Versão:** 1.0
