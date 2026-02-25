# Matriz de Validação — Enterprise Features Self-hosted

**Data:** 2026-02-25  
**Objetivo:** Validar funcionalidades Enterprise habilitadas sem regressões

## 1. Pré-validação (Ambiente)

| Check | Esperado | Comando/Verificação | Status |
|-------|----------|---------------------|--------|
| Enterprise mode ativo | `true` | `ChatwootApp.enterprise?` | ✅ Validado |
| Self-hosted Enterprise | `true` | `ChatwootApp.self_hosted_enterprise?` | ✅ Validado |
| Pricing plan | `'enterprise'` | `ChatwootHub.pricing_plan` | ✅ Validado |
| Account features | 8 features Enterprise | `account.feature_enabled?(:sla)` | ✅ Validado |

## 2. Validação de API Endpoints

### 2.1. Endpoint limits (antes quebrado)

| Teste | Método | Endpoint | Esperado | Status |
|-------|--------|----------|----------|--------|
| GET limits | `GET` | `/enterprise/api/v1/accounts/:id/limits` | `200 OK` com limites vazios | ⏳ Pendente |
| Response structure | - | - | `{ id, limits: { conversation, agents, ... } }` | ⏳ Pendente |
| Console errors | - | - | Sem erros 404 no console | ⏳ Pendente |

**Comando de teste:**
```bash
# Login como admin, obter token, testar:
curl -H "api_access_token: YOUR_TOKEN" \
  http://localhost:3000/enterprise/api/v1/accounts/1/limits
```

## 3. Validação de Features Enterprise (UI)

### 3.1. SLA (Service Level Agreements)

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → SLA | - | Menu "SLA" aparece | ⏳ Pendente |
| Criar política | SLA → New | Criar política teste | Política criada com sucesso | ⏳ Pendente |
| Aplicar a inbox | SLA → Edit | Associar a inbox | Inbox com SLA ativo | ⏳ Pendente |
| Conversa com SLA | Conversation | Criar nova conversa | Badge/timer SLA visível | ⏳ Pendente |

### 3.2. Custom Roles (Papéis Customizados)

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → Teams & Agents | - | Tab "Custom Roles" aparece | ⏳ Pendente |
| Criar papel | Custom Roles → New | Criar papel "Support L1" | Papel criado com permissões | ⏳ Pendente |
| Atribuir a agente | Team Members → Edit | Atribuir papel customizado | Agente com papel customizado | ⏳ Pendente |
| Validar permissões | Login como agente | Testar ações restritas | Permissões respeitadas | ⏳ Pendente |

### 3.3. Audit Logs

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → Audit Logs | - | Menu "Audit Logs" aparece | ⏳ Pendente |
| Logs registrados | Audit Logs | Visualizar lista | Logs de ações recentes visíveis | ⏳ Pendente |
| Filtrar por usuário | Audit Logs → Filter | Filtrar por admin | Logs filtrados corretamente | ⏳ Pendente |
| Log de mudança | Fazer ação (ex: criar inbox) | Verificar audit log | Ação registrada no log | ⏳ Pendente |

### 3.4. Disable Branding

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Branding removido | Dashboard geral | - | Logo/marca Chatwoot não aparece | ⏳ Pendente |
| Widget sem marca | Widget público | Testar widget | Powered by Chatwoot removido | ⏳ Pendente |
| Help center | Portal público | - | Branding Chatwoot removido | ⏳ Pendente |

### 3.5. SAML (SSO)

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → Security → SAML | - | Opção SAML aparece | ⏳ Pendente |
| Configuração | SAML Settings | - | Formulário de config visível | ⏳ Pendente |
| ⚠️ **NOTA** | - | - | Requer IdP configurado para teste completo | - |

### 3.6. CSAT Review Notes

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Campo de notas | Reports → CSAT | Abrir resposta CSAT | Campo "Notes" visível | ⏳ Pendente |
| Adicionar nota | CSAT → Add note | Adicionar nota interna | Nota salva com sucesso | ⏳ Pendente |
| Visualizar notas | CSAT list | - | Notas aparecem na listagem | ⏳ Pendente |

### 3.7. Conversation Required Attributes

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → Conversation Workflow | - | Menu aparece | ⏳ Pendente |
| Configurar atributo | Required Attributes → Add | Adicionar atributo obrigatório | Atributo adicionado | ⏳ Pendente |
| Modal ao resolver | Conversa → Resolve | Tentar resolver sem preencher | Modal exige preenchimento | ⏳ Pendente |
| Validação | Modal → Resolve | Resolver sem preencher | Validação impede resolução | ⏳ Pendente |

### 3.8. Advanced Assignment

| Teste | Navegação | Ação | Esperado | Status |
|-------|-----------|------|----------|--------|
| Menu visível | Settings → Inboxes → Assignment | - | Opções avançadas aparecem | ⏳ Pendente |
| Regras de assignment | Advanced Assignment | Criar regra complexa | Regra criada com sucesso | ⏳ Pendente |
| Validar assignment | Nova conversa | - | Conversa atribuída conforme regra | ⏳ Pendente |

## 4. Validação de Não-regressão

### 4.1. Contas não-Enterprise (se houver)

| Teste | Contexto | Esperado | Status |
|-------|----------|----------|--------|
| Features desabilitadas | Conta sem features Enterprise | Menus/features não aparecem | ⏳ Pendente |
| API retorna 403 | Tentar acessar feature sem permissão | `403 Forbidden` | ⏳ Pendente |

### 4.2. Features OSS não afetadas

| Teste | Feature | Esperado | Status |
|-------|---------|----------|--------|
| Conversas básicas | Criar/responder/resolver | Funcionamento normal | ⏳ Pendente |
| Inboxes | Criar/editar inbox | Funcionamento normal | ⏳ Pendente |
| Agentes | Adicionar/remover agente | Funcionamento normal | ⏳ Pendente |
| Teams | Criar/editar team | Funcionamento normal | ⏳ Pendente |
| Macros | Criar/usar macro | Funcionamento normal | ⏳ Pendente |
| Automações | Criar/executar automação | Funcionamento normal | ⏳ Pendente |

## 5. Validação de Console/Logs

### 5.1. Frontend (Browser Console)

| Check | Esperado | Status |
|-------|----------|--------|
| Sem erros 404 de limits | Console limpo ao carregar dashboard | ⏳ Pendente |
| Sem erros JS | Sem erros não tratados | ⏳ Pendente |
| Sem warnings críticos | Apenas warnings de dev aceitáveis | ⏳ Pendente |

### 5.2. Backend (Rails Logs)

| Check | Esperado | Status |
|-------|----------|--------|
| Sem erros 500 | Logs sem Internal Server Error | ⏳ Pendente |
| Rotas Enterprise montadas | `rake routes | grep enterprise` mostra rotas | ⏳ Pendente |
| Feature checks funcionando | Sem erros de feature undefined | ⏳ Pendente |

**Comando de verificação:**
```bash
# Checar rotas Enterprise
cd /home/cesar/chatwoot
bundle exec rake routes | grep enterprise | grep limits

# Monitorar logs em tempo real
tail -f log/development.log
```

## 6. Checklist de Validação Rápida (Smoke Test)

Para validação rápida após implementação, executar na ordem:

- [ ] 1. Restart Rails server (`overmind restart`)
- [ ] 2. Login como admin
- [ ] 3. Abrir console do browser (F12)
- [ ] 4. Verificar que não há erro 404 de `/limits`
- [ ] 5. Navegar para Settings e confirmar que novos menus aparecem:
  - [ ] SLA
  - [ ] Conversation Workflow
  - [ ] Audit Logs
  - [ ] Custom Roles (dentro de Teams & Agents)
- [ ] 6. Testar criar um registro em cada feature crítica:
  - [ ] Criar política SLA
  - [ ] Adicionar atributo obrigatório
  - [ ] Ver audit logs
- [ ] 7. Verificar branding removido (sem logo Chatwoot)
- [ ] 8. Testar conversa básica (não-regressão)

## 7. Critérios de Sucesso

✅ **Aprovado para produção/lab** quando:
- Todas as validações de API retornam 200 (não 404)
- Todos os menus Enterprise aparecem na UI
- Pelo menos 1 teste por feature funciona (criar/visualizar)
- Nenhuma regressão em features OSS
- Console sem erros críticos

⚠️ **Requer ajustes** se:
- Algum menu não aparece
- Erro 404 ainda presente
- Feature quebrada ou não funcional

❌ **Rollback necessário** se:
- Features OSS quebradas
- Impossível fazer login
- Erros críticos em produção
