# Scripts de Setup - Chatwoot

Scripts de configuração inicial do ambiente Chatwoot.

## Scripts Disponíveis

### 📦 production.sh

**Propósito:** Setup completo do servidor de produção Ubuntu 24.04

**Uso:**
```bash
sudo DOMAIN=chat.exemplo.com bash doc/scripts/setup/production.sh
```

**O que instala:**
- PostgreSQL 16 + pgvector
- Redis
- Nginx (configuração otimizada)
- Ruby 3.4.4 (via rbenv)
- Node 24 + pnpm
- Certbot (Let's Encrypt)
- UFW (firewall)

**O que configura:**
- Usuário dedicado `chatwoot`
- Serviços systemd (Puma, Sidekiq)
- Nginx com upstream keepalive
- SSL/TLS robusto
- Firewall
- Logs dedicados

**Tempo estimado:** 10-20 minutos

---

### 🔧 dev.sh

**Propósito:** Setup do ambiente de desenvolvimento local

**Uso:**
```bash
bash doc/scripts/setup/dev.sh
```

**O que instala:**
- PostgreSQL 16
- Redis
- Ruby 3.4.4 (via rbenv)
- Node 24 + pnpm
- Dependências do sistema

**O que configura:**
- Bancos de dados (dev, test)
- Peer authentication (sem senha)
- Dependências Ruby e Node

**Tempo estimado:** 5-10 minutos

---

## Comparação: Dev vs Produção

| Aspecto | dev.sh | production.sh |
|---------|--------|---------------|
| **Usuário** | Usuário atual | Usuário dedicado `chatwoot` |
| **Nginx** | ❌ Não | ✅ Sim (otimizado) |
| **SSL** | ❌ Não | ✅ Let's Encrypt |
| **Firewall** | ❌ Não | ✅ UFW |
| **systemd** | ❌ Não | ✅ Puma + Sidekiq |
| **PostgreSQL** | Peer auth | Password |
| **Logs** | Console | systemd + Nginx |
| **Process Manager** | Overmind | systemd |

## Próximos Passos

### Após `dev.sh`
1. Configure `.env` local
2. Execute `bundle exec rails db:prepare`
3. Execute `pnpm run start:dev`

### Após `production.sh`
1. Clone o código Chatwoot
2. Configure `.env` de produção
3. Execute `production/deploy.sh`
4. Configure SSL com Certbot
5. Execute `production/verify.sh`

## Documentação

- **Produção:** Veja `../production/README.md`
- **Índice geral:** Veja `../README.md`

---

**Última atualização:** 25/02/2026
