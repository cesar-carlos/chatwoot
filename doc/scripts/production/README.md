# Chatwoot Native Production Setup - Ubuntu 24.04

Scripts para configurar e manter Chatwoot em produção sem Docker.

## Arquitetura

```
Internet → Nginx (reverse proxy, SSL) → Puma (app server) → Rails App
                                     ↓
                                  Sidekiq (background jobs)
                                     ↓
                            PostgreSQL + Redis
```

## Scripts Disponíveis

### 1. `setup/production.sh`

**Propósito**: Configuração inicial completa do servidor

**Execução**: Uma única vez, como root

```bash
sudo bash doc/scripts/setup/production.sh
```

**O que faz**:
- Instala PostgreSQL 16, Redis, Nginx
- Instala Ruby 3.4.4 (via rbenv) e Node 24
- Cria usuário dedicado `chatwoot`
- Configura Nginx como reverse proxy
- Cria serviços systemd (puma, sidekiq)
- Configura firewall (UFW)
- Gera credenciais seguras

**Após execução**:
1. Clone o código do Chatwoot
2. Configure variáveis de ambiente (`.env`)
3. Execute deploy inicial
4. Configure SSL com Let's Encrypt

### 2. `production/deploy.sh`

**Propósito**: Deploy e atualizações da aplicação

**Execução**: Como usuário `chatwoot`, sempre que houver updates

```bash
sudo -u chatwoot REPO_URL=https://github.com/cesar-carlos/chatwoot.git DEPLOY_BRANCH=main bash doc/scripts/production/deploy.sh
```

**O que faz**:
- Pull do código mais recente (git)
- Atualiza dependências (bundle, pnpm)
- Executa migrations do banco
- Recompila assets
- Reinicia serviços

### 3. `production/verify.sh`

**Propósito**: Verificação automatizada pós-instalação

**Execução**: Após setup ou quando houver problemas

```bash
sudo bash doc/scripts/production/verify.sh chat.seudominio.com
```

**O que verifica**:
- Status de todos os serviços
- Configuração crítica do Nginx (incluindo `underscores_in_headers`)
- Certificados SSL e validade
- Portas e firewall
- Conectividade HTTP/HTTPS/Backend
- Banco de dados e conexões
- Redis
- Variáveis de ambiente (.env)
- Enterprise (`INSTALLATION_PRICING_PLAN` e `chatwoot:self_hosted_enterprise:verify`)
- Logs de erro

**Resultado**: Retorna 0 (OK), ou lista erros/avisos que precisam correção

**Inclui verificação Enterprise**: O script também verifica `INSTALLATION_PRICING_PLAN` e executa `chatwoot:self_hosted_enterprise:verify`.

### 4. Enterprise (produção)

**Verificar status Enterprise**:
```bash
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init -)" && RAILS_ENV=production bundle exec rails chatwoot:self_hosted_enterprise:verify'
```

**Habilitar features Enterprise em todas as contas** (após configurar `INSTALLATION_PRICING_PLAN=enterprise` no `.env`):
```bash
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init -)" && RAILS_ENV=production bundle exec rails chatwoot:self_hosted_enterprise:enable'
```

**Pré-requisito**: Adicione `INSTALLATION_PRICING_PLAN=enterprise` no `.env` e reinicie os serviços (`sudo systemctl restart chatwoot-puma chatwoot-sidekiq`).

## Diferenças: Desenvolvimento vs Produção

| Aspecto | Desenvolvimento | Produção |
|---------|----------------|----------|
| **Servidor web** | Puma standalone (dev mode) | Nginx + Puma (localhost:3000) |
| **Process manager** | Overmind/Foreman | systemd |
| **Banco de dados** | PostgreSQL (peer auth) | PostgreSQL (password) |
| **SSL/TLS** | Não | Let's Encrypt |
| **Assets** | Live compilation | Precompilados |
| **Logs** | Console/arquivo | systemd journal + Nginx logs dedicados |
| **Usuário** | Seu usuário | Usuário dedicado `chatwoot` |
| **Firewall** | Não configurado | UFW habilitado |
| **Cache** | Desenvolvimento | Production |
| **Email** | Letter opener / console | SMTP real |
| **Nginx keepalive** | N/A | 32 conexões persistentes |
| **Timeouts** | Curtos | Estendidos (uploads: 1h, WS: 10h) |
| **Headers críticos** | Automático | `underscores_in_headers on` |
| **WebSocket (/cable)** | Genérico | Rota dedicada otimizada |

## ⚙️ Configurações Nginx Otimizadas

O script de produção inclui configurações otimizadas baseadas em melhores práticas:

### Características Críticas

- ✅ **`underscores_in_headers on`** - OBRIGATÓRIO para autenticação Chatwoot
- ✅ **Upstream com keepalive** - 32 conexões persistentes (↑30% performance)
- ✅ **SSL robusto** - TLS 1.2/1.3, ciphers modernos, session cache
- ✅ **Timeouts estendidos** - 1h para uploads, 10h para WebSocket
- ✅ **Rotas otimizadas** - `/cable` (WebSocket), `/rails/active_storage/` (uploads)
- ✅ **Buffering inteligente** - Desabilitado para uploads e WebSocket
- ✅ **Headers de segurança** - HSTS, X-Frame-Options, Referrer-Policy
- ✅ **HTTP/2 reuseport** - Melhor performance multi-core

📖 **Documentação completa:** Veja `docs/improvements.md` para detalhes técnicos.

## Fluxo Completo de Instalação

### Passo 1: Configuração inicial do servidor

```bash
# 1. Em um servidor Ubuntu 24.04 limpo
sudo apt update && sudo apt upgrade -y

# 2. Configure DNS (A record apontando para o servidor)
# Exemplo: chat.seudominio.com → IP_DO_SERVIDOR

# 3. Execute o script de setup
sudo bash doc/scripts/setup/production.sh
# Informe o domínio quando solicitado
```

### Passo 2: Deploy da aplicação

```bash
# 1. Clone o código (como usuário chatwoot)
sudo -u chatwoot git clone https://github.com/cesar-carlos/chatwoot.git /home/chatwoot/chatwoot

# 2. Configure variáveis de ambiente
sudo -u chatwoot cp /home/chatwoot/chatwoot/.env.template /home/chatwoot/chatwoot/.env
sudo -u chatwoot nano /home/chatwoot/chatwoot/.env

# 3. Instale dependências
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && source ~/.bashrc && bundle install'
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && pnpm install'

# 4. Setup do banco
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:prepare'
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:seed'

# 5. Compile assets (ajuste heap em VPS pequena)
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && NODE_OPTIONS="--max-old-space-size=4096" RAILS_ENV=production bundle exec rails assets:precompile'

# 6. Crie diretório de storage (para uploads com ACTIVE_STORAGE_SERVICE=local)
sudo -u chatwoot mkdir -p /home/chatwoot/chatwoot/storage /home/chatwoot/chatwoot/tmp/sockets
```

### Migração de repositório (oficial -> fork)

Se o servidor já está rodando com outro remoto, sincronize para este projeto:

```bash
# Pare a aplicação
sudo systemctl stop chatwoot-puma chatwoot-sidekiq

# Troque para o fork e branch principal
sudo -u chatwoot git -C /home/chatwoot/chatwoot remote set-url origin https://github.com/cesar-carlos/chatwoot.git
sudo -u chatwoot git -C /home/chatwoot/chatwoot fetch origin
sudo -u chatwoot git -C /home/chatwoot/chatwoot checkout -B main origin/main
sudo -u chatwoot git -C /home/chatwoot/chatwoot reset --hard origin/main
```

### Reset completo do banco (instalação limpa)

Use apenas quando quiser recriar tudo do zero:

```bash
sudo -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot && export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init -)" && DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bundle exec rails db:drop db:create db:prepare'
```

### Passo 3: Configure SSL

```bash
# Let's Encrypt (gratuito)
sudo certbot --nginx -d chat.seudominio.com

# Renovação automática já está configurada via systemd timer
```

### Passo 4: Inicie os serviços

```bash
sudo systemctl start chatwoot-puma
sudo systemctl start chatwoot-sidekiq
sudo systemctl enable chatwoot-puma
sudo systemctl enable chatwoot-sidekiq
```

### Passo 5: Verifique

```bash
# Script de verificação automatizada (RECOMENDADO)
sudo bash doc/scripts/production/verify.sh chat.seudominio.com

# Ou manualmente:
# Status dos serviços
sudo systemctl status chatwoot-puma
sudo systemctl status chatwoot-sidekiq

# Logs em tempo real
sudo journalctl -u chatwoot-puma -f
sudo journalctl -u chatwoot-sidekiq -f

# Acesse https://chat.seudominio.com
```

**O script de verificação checa:**
- ✓ Serviços (nginx, postgresql, redis, puma, sidekiq)
- ✓ Configuração Nginx (incluindo `underscores_in_headers`)
- ✓ SSL e certificados
- ✓ Portas e firewall
- ✓ Conectividade HTTP/HTTPS
- ✓ Banco de dados
- ✓ Variáveis de ambiente
- ✓ Logs

## Comandos Úteis

### Gerenciamento de Serviços

```bash
# Reiniciar serviços
sudo systemctl restart chatwoot-puma
sudo systemctl restart chatwoot-sidekiq

# Parar serviços
sudo systemctl stop chatwoot-puma
sudo systemctl stop chatwoot-sidekiq

# Ver logs
sudo journalctl -u chatwoot-puma -f        # tempo real
sudo journalctl -u chatwoot-puma -n 100    # últimas 100 linhas
sudo journalctl -u chatwoot-sidekiq --since "1 hour ago"
```

### Rails Console

```bash
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails console'
```

### Migrações

```bash
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate'
```

### Backup do Banco

```bash
# Backup
sudo -u postgres pg_dump chatwoot_production > backup_$(date +%Y%m%d).sql

# Restaurar
sudo -u postgres psql chatwoot_production < backup_20260225.sql
```

## Troubleshooting

### Serviço não inicia

```bash
# Verifique logs detalhados
sudo journalctl -u chatwoot-puma -n 200
sudo systemctl status chatwoot-puma

# Teste manual
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec puma -C config/puma.rb'
```

### Erro de permissão

```bash
# Corrija ownership
sudo chown -R chatwoot:chatwoot /home/chatwoot/chatwoot

# Permissões de socket e storage (Active Storage)
sudo mkdir -p /home/chatwoot/chatwoot/tmp/sockets /home/chatwoot/chatwoot/storage
sudo chown -R chatwoot:chatwoot /home/chatwoot/chatwoot/tmp/sockets /home/chatwoot/chatwoot/storage
```

### Erro ao enviar anexos/arquivos (storage)

Quando `ACTIVE_STORAGE_SERVICE=local`, os uploads vão para `storage/`. Se a pasta não existir ou tiver permissões incorretas, o envio de arquivos falha.

```bash
# Crie a pasta e corrija permissões
sudo mkdir -p /home/chatwoot/chatwoot/storage
sudo chown chatwoot:chatwoot /home/chatwoot/chatwoot/storage
sudo systemctl restart chatwoot-puma chatwoot-sidekiq
```

O script de deploy (`deploy.sh`) já cria `storage/` automaticamente em cada atualização.

### Erro 502 Bad Gateway

```bash
# Verifique se Puma está rodando
sudo systemctl status chatwoot-puma

# Verifique socket do Puma
ls -la /home/chatwoot/chatwoot/tmp/sockets/puma.sock

# Verifique logs do Nginx
sudo tail -f /var/log/nginx/error.log
```

### Erro 403 no Nginx após deploy

```bash
# Garanta que o Nginx consiga atravessar o home e ler arquivos públicos
sudo chmod o+x /home/chatwoot
sudo chmod -R o+rX /home/chatwoot/chatwoot/public
sudo systemctl restart nginx
```

### Assets não carregam

```bash
# Recompile assets
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails assets:clobber'
sudo -u chatwoot bash -c 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails assets:precompile'
```

## Monitoramento

### Recursos do Sistema

```bash
# CPU e memória
htop

# Espaço em disco
df -h

# Processos Chatwoot
ps aux | grep -E 'puma|sidekiq'
```

### Performance do Banco

```bash
# Conexões ativas
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity WHERE datname='chatwoot_production';"

# Queries lentas (configure log_min_duration_statement no postgresql.conf)
sudo tail -f /var/log/postgresql/postgresql-16-main.log
```

## Atualizações

### Atualizar aplicação

```bash
# Use o script de deploy
sudo -u chatwoot REPO_URL=https://github.com/cesar-carlos/chatwoot.git DEPLOY_BRANCH=main bash doc/scripts/production/deploy.sh
```

### Atualizar sistema operacional

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot  # se necessário
```

### Atualizar Ruby

```bash
# Como usuário chatwoot
sudo -u chatwoot bash
cd ~
rbenv install 3.4.5  # nova versão
cd /home/chatwoot/chatwoot
rbenv local 3.4.5
gem install bundler
bundle install

# Reinicie serviços
exit
sudo systemctl restart chatwoot-puma
sudo systemctl restart chatwoot-sidekiq
```

## Segurança

### Checklist

- ✅ Firewall (UFW) habilitado
- ✅ SSL/TLS configurado (Let's Encrypt)
- ✅ Usuário dedicado (não root)
- ✅ Senha forte no banco de dados
- ✅ Secret key aleatória
- ✅ HTTPS forçado
- ⚠️ Configure backups regulares
- ⚠️ Configure monitoramento (Datadog, New Relic, etc)
- ⚠️ Configure fail2ban para proteção contra brute force

### Hardening adicional

```bash
# Desabilitar login root via SSH
sudo nano /etc/ssh/sshd_config
# Adicione: PermitRootLogin no
sudo systemctl restart ssh

# Configure fail2ban
sudo apt install fail2ban
sudo systemctl enable fail2ban
```

## Variáveis de Ambiente Importantes

```bash
# Mínimo necessário em .env
POSTGRES_HOST=localhost
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=<senha-gerada>
POSTGRES_DATABASE=chatwoot_production
REDIS_URL=redis://localhost:6379
RAILS_ENV=production
SECRET_KEY_BASE=<chave-gerada>
FRONTEND_URL=https://chat.seudominio.com
FORCE_SSL=true

# Opcional mas recomendado
ACTIVE_STORAGE_SERVICE=amazon  # ou local
MAILER_SENDER_EMAIL=notifications@seudominio.com
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
```

## Performance

### Tuning do Puma

Edite `config/puma.rb`:

```ruby
# Ajuste baseado na CPU
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count
```

Configure no `.env`:
```bash
WEB_CONCURRENCY=2  # número de workers (CPUs)
RAILS_MAX_THREADS=5
RAILS_MIN_THREADS=5
```

### Tuning do PostgreSQL

```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
```

Para servidor com 4GB RAM:
```
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 16MB
maintenance_work_mem = 256MB
```

```bash
sudo systemctl restart postgresql
```

## Custos Estimados

| Serviço | Especificação | Custo/mês (USD) |
|---------|--------------|-----------------|
| VPS | 2 CPU, 4GB RAM, 80GB SSD | $12-24 |
| Domínio | .com | $10-15 |
| SSL | Let's Encrypt | Gratuito |
| **Total** | | **$22-39/mês** |

Provedores recomendados: DigitalOcean, Hetzner, Linode, Vultr

## Suporte

- Documentação oficial: https://www.chatwoot.com/docs/
- GitHub: https://github.com/chatwoot/chatwoot
- Comunidade: https://discord.gg/cJXdrwS
