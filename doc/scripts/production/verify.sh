#!/bin/bash
# Script de Verificação Pós-Instalação Chatwoot
# Verifica se todas as configurações críticas estão corretas

set -e

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  read -p "Digite o domínio (ex: chat.example.com): " DOMAIN
fi

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

echo "========================================"
echo "  Verificação Chatwoot Produção"
echo "  Domínio: $DOMAIN"
echo "========================================"
echo ""

ERRORS=0
WARNINGS=0

# 1. Verificar serviços systemd
echo "1️⃣  Verificando serviços..."
if systemctl is-active --quiet nginx; then
  pass "Nginx está rodando"
else
  fail "Nginx NÃO está rodando"
  ((ERRORS++))
fi

if systemctl is-active --quiet postgresql; then
  pass "PostgreSQL está rodando"
else
  fail "PostgreSQL NÃO está rodando"
  ((ERRORS++))
fi

if systemctl is-active --quiet redis-server; then
  pass "Redis está rodando"
else
  fail "Redis NÃO está rodando"
  ((ERRORS++))
fi

if systemctl is-active --quiet chatwoot-puma; then
  pass "Chatwoot Puma está rodando"
else
  fail "Chatwoot Puma NÃO está rodando"
  ((ERRORS++))
fi

if systemctl is-active --quiet chatwoot-sidekiq; then
  pass "Chatwoot Sidekiq está rodando"
else
  fail "Chatwoot Sidekiq NÃO está rodando"
  ((ERRORS++))
fi
echo ""

# 2. Verificar configuração Nginx
echo "2️⃣  Verificando configuração Nginx..."
if nginx -t &>/dev/null; then
  pass "Sintaxe do Nginx OK"
else
  fail "Erro na sintaxe do Nginx"
  ((ERRORS++))
fi

if grep -q "underscores_in_headers on" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "underscores_in_headers habilitado (CRÍTICO)"
else
  fail "underscores_in_headers NÃO habilitado (CRÍTICO - autenticação falhará)"
  ((ERRORS++))
fi

if grep -q "keepalive 32" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "Keepalive upstream configurado"
else
  warn "Keepalive upstream não configurado (performance reduzida)"
  ((WARNINGS++))
fi

if grep -q "location /cable" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "Rota /cable dedicada (WebSocket)"
else
  warn "Rota /cable não dedicada (WebSocket pode ser instável)"
  ((WARNINGS++))
fi

if grep -q "location /rails/active_storage" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "Rota /rails/active_storage otimizada"
else
  warn "Rota /rails/active_storage não otimizada"
  ((WARNINGS++))
fi

if grep -q "proxy_read_timeout 36000s" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "Timeouts estendidos configurados"
else
  warn "Timeouts podem ser muito curtos para uploads grandes"
  ((WARNINGS++))
fi
echo ""

# 3. Verificar SSL
echo "3️⃣  Verificando SSL..."
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  pass "Certificado SSL encontrado"
  
  # Verificar validade
  EXPIRY=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate | cut -d= -f2)
  info "Expira em: $EXPIRY"
  
  DAYS_LEFT=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / 86400 ))
  if [ $DAYS_LEFT -lt 30 ]; then
    warn "Certificado expira em $DAYS_LEFT dias (renovar em breve)"
    ((WARNINGS++))
  else
    pass "Certificado válido por $DAYS_LEFT dias"
  fi
else
  fail "Certificado SSL NÃO encontrado"
  ((ERRORS++))
fi

if grep -q "ssl_protocols TLSv1.2 TLSv1.3" /etc/nginx/sites-available/chatwoot 2>/dev/null; then
  pass "TLS 1.2/1.3 configurado"
else
  warn "Versões antigas de TLS podem estar habilitadas"
  ((WARNINGS++))
fi

if [ -f "/etc/ssl/dhparam" ]; then
  pass "DH parameters encontrados"
else
  warn "DH parameters não encontrados (gerar com: openssl dhparam -out /etc/ssl/dhparam 2048)"
  ((WARNINGS++))
fi

# Verificar renovação automática
if crontab -l 2>/dev/null | grep -q "certbot renew"; then
  pass "Renovação automática SSL configurada"
else
  warn "Renovação automática SSL não configurada"
  ((WARNINGS++))
fi
echo ""

# 4. Verificar portas
echo "4️⃣  Verificando portas..."
if netstat -tlnp 2>/dev/null | grep -q ":80.*LISTEN"; then
  pass "Porta 80 (HTTP) aberta"
else
  fail "Porta 80 (HTTP) NÃO está aberta"
  ((ERRORS++))
fi

if netstat -tlnp 2>/dev/null | grep -q ":443.*LISTEN"; then
  pass "Porta 443 (HTTPS) aberta"
else
  fail "Porta 443 (HTTPS) NÃO está aberta"
  ((ERRORS++))
fi

# Verificar se Puma está usando socket Unix
if [ -S "/home/chatwoot/chatwoot/tmp/sockets/puma.sock" ]; then
  pass "Socket Unix do Puma encontrado"
else
  warn "Socket Unix do Puma não encontrado (Puma pode não estar rodando)"
  ((WARNINGS++))
fi

# Verificar diretório storage (Active Storage com ACTIVE_STORAGE_SERVICE=local)
if [ -d "/home/chatwoot/chatwoot/storage" ]; then
  pass "Diretório storage existe (uploads)"
else
  warn "Diretório storage não existe (criar: mkdir -p /home/chatwoot/chatwoot/storage && chown chatwoot:chatwoot)"
  ((WARNINGS++))
fi
echo ""

# 5. Testes de conectividade
echo "5️⃣  Testando conectividade..."

# Teste HTTP (deve redirecionar)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  pass "HTTP redireciona para HTTPS (código $HTTP_CODE)"
elif [ "$HTTP_CODE" = "200" ]; then
  warn "HTTP retorna 200 (deveria redirecionar para HTTPS)"
  ((WARNINGS++))
else
  fail "HTTP retorna erro (código $HTTP_CODE)"
  ((ERRORS++))
fi

# Teste HTTPS
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" 2>/dev/null || echo "000")
if [ "$HTTPS_CODE" = "200" ]; then
  pass "HTTPS funciona (código 200)"
elif [ "$HTTPS_CODE" = "000" ]; then
  fail "HTTPS não responde (verificar DNS e SSL)"
  ((ERRORS++))
else
  warn "HTTPS retorna código $HTTPS_CODE (pode ser normal se app não estiver configurado)"
  ((WARNINGS++))
fi

# Teste backend local
BACKEND_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:3000" 2>/dev/null || echo "000")
if [ "$BACKEND_CODE" = "200" ] || [ "$BACKEND_CODE" = "302" ]; then
  pass "Backend Chatwoot responde (código $BACKEND_CODE)"
else
  fail "Backend Chatwoot NÃO responde (código $BACKEND_CODE)"
  ((ERRORS++))
fi
echo ""

# 6. Verificar firewall
echo "6️⃣  Verificando firewall..."
if command -v ufw &>/dev/null; then
  if ufw status | grep -q "Status: active"; then
    pass "UFW está ativo"
    
    if ufw status | grep -q "80.*ALLOW"; then
      pass "Porta 80 permitida no firewall"
    else
      fail "Porta 80 NÃO permitida no firewall"
      ((ERRORS++))
    fi
    
    if ufw status | grep -q "443.*ALLOW"; then
      pass "Porta 443 permitida no firewall"
    else
      fail "Porta 443 NÃO permitida no firewall"
      ((ERRORS++))
    fi
  else
    warn "UFW não está ativo"
    ((WARNINGS++))
  fi
else
  info "UFW não instalado"
fi
echo ""

# 7. Verificar logs
echo "7️⃣  Verificando logs..."
if [ -f "/var/log/nginx/chatwoot_error_443.log" ]; then
  pass "Logs Nginx dedicados configurados"
  
  ERROR_COUNT=$(grep -c "error" /var/log/nginx/chatwoot_error_443.log 2>/dev/null || echo 0)
  if [ $ERROR_COUNT -gt 0 ]; then
    warn "Encontrados $ERROR_COUNT erros nos logs do Nginx (últimas 24h)"
    info "Ver: tail -n 50 /var/log/nginx/chatwoot_error_443.log"
    ((WARNINGS++))
  else
    pass "Sem erros recentes nos logs"
  fi
else
  warn "Logs Nginx dedicados não encontrados"
  ((WARNINGS++))
fi
echo ""

# 8. Verificar banco de dados
echo "8️⃣  Verificando banco de dados..."
if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw chatwoot_production; then
  pass "Banco chatwoot_production existe"
  
  # Verificar conexões
  CONN_COUNT=$(sudo -u postgres psql -tAc "SELECT count(*) FROM pg_stat_activity WHERE datname='chatwoot_production';" 2>/dev/null || echo "0")
  if [ $CONN_COUNT -gt 0 ]; then
    pass "Banco tem $CONN_COUNT conexão(ões) ativa(s)"
  else
    warn "Banco não tem conexões ativas (app pode não estar conectado)"
    ((WARNINGS++))
  fi
else
  fail "Banco chatwoot_production NÃO existe"
  ((ERRORS++))
fi
echo ""

# 9. Verificar Redis
echo "9️⃣  Verificando Redis..."
if redis-cli ping &>/dev/null | grep -q "PONG"; then
  pass "Redis responde"
else
  fail "Redis NÃO responde"
  ((ERRORS++))
fi
echo ""

# 10. Verificar variáveis de ambiente
echo "🔟 Verificando variáveis de ambiente..."
if [ -f "/home/chatwoot/chatwoot/.env" ]; then
  pass "Arquivo .env encontrado"
  
  if grep -q "^FRONTEND_URL=https://$DOMAIN" /home/chatwoot/chatwoot/.env 2>/dev/null; then
    pass "FRONTEND_URL configurado corretamente"
  else
    warn "FRONTEND_URL pode não estar configurado corretamente"
    info "Deve ser: FRONTEND_URL=https://$DOMAIN"
    ((WARNINGS++))
  fi
  
  if grep -q "^RAILS_ENV=production" /home/chatwoot/chatwoot/.env 2>/dev/null; then
    pass "RAILS_ENV=production"
  else
    fail "RAILS_ENV não está como production"
    ((ERRORS++))
  fi
  
  if grep -q "^SECRET_KEY_BASE=" /home/chatwoot/chatwoot/.env 2>/dev/null; then
    pass "SECRET_KEY_BASE configurado"
  else
    fail "SECRET_KEY_BASE não configurado"
    ((ERRORS++))
  fi
else
  fail "Arquivo .env NÃO encontrado"
  ((ERRORS++))
fi
echo ""

# Resumo
echo "========================================"
echo "  RESUMO"
echo "========================================"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo -e "${GREEN}✓ TUDO OK!${NC} Sistema pronto para produção."
  echo ""
  info "Próximos passos:"
  info "  1. Testar aplicação: https://$DOMAIN"
  info "  2. Criar primeiro usuário admin"
  info "  3. Configurar SMTP para emails"
  info "  4. Configurar backup automático"
  exit 0
elif [ $ERRORS -eq 0 ]; then
  echo -e "${YELLOW}⚠ $WARNINGS aviso(s)${NC} - Sistema funcional mas pode ser otimizado"
  echo ""
  info "Revise os avisos acima para otimizar o sistema"
  exit 0
else
  echo -e "${RED}✗ $ERRORS erro(s) crítico(s)${NC}"
  if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS aviso(s)${NC}"
  fi
  echo ""
  fail "Sistema NÃO está pronto para produção"
  echo ""
  info "Corrija os erros críticos acima antes de usar em produção"
  exit 1
fi
