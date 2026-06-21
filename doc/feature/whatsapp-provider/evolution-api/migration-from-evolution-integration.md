# Migração — integração Evolution→Chatwoot legada → provider nativo

Guia para operadores que já usam a integração **built-in** da Evolution (`POST /chatwoot/set`, inbox tipo `api` no Chatwoot) e querem migrar para **`Channel::Whatsapp`** com `provider: 'evolution'` no fork.

**Relacionados:** [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md) · [decisions.md](./decisions.md) §7 · [troubleshooting.md](./troubleshooting.md)

---

## Antes de começar

| Item | Verificar |
|------|-----------|
| Versão Evolution | Congelar em **2.3.x** — ver [evolution-target-version.txt](./evolution-target-version.txt) |
| Licença 2.4+ | Se `503 LICENSE_REQUIRED`, ativar em [docs licensing](https://docs.evolutionfoundation.com.br/licensing) antes de qualquer migração |
| Backup | Exportar conversas críticas; snapshot do banco Chatwoot |
| Janela de manutenção | Migração exige **parar** o fluxo de mensagens por alguns minutos |

---

## O que muda

| Aspecto | Legado (Evolution→CW) | Provider nativo (fork) |
|---------|----------------------|------------------------|
| Quem configura quem | Evolution chama Chatwoot SDK | Chatwoot chama Evolution REST |
| Tipo de inbox | `api` | `Channel::Whatsapp` `provider: 'evolution'` |
| Webhook inbound CW | `/chatwoot/webhook/:instance` (Evolution recebe) | `/webhooks/evolution/:instance_name` (Chatwoot recebe) |
| `source_id` | Prefixo `WAID:` | `key.id` Baileys (sem prefixo) |
| Import histórico | SQL direto no Postgres CW (opcional) | API `findContacts` / `findMessages` (Fase 4) |
| Janela 24h | N/A (inbox API) | Bypass explícito no fork |

---

## Passo a passo

### 1. Criar o novo inbox (sem desligar o legado ainda)

1. No Chatwoot fork: **Settings → Inboxes → Add → Evolution API**
2. Preencher `base_url`, `api_key`, `instance_name` (**mesma instância** Evolution existente ou nova — ver [decisions.md §3](./decisions.md))
3. Conectar QR se necessário (`connection_status` → `open`)
4. Confirmar que o webhook Evolution aponta para:
   ```
   https://{FRONTEND_URL}/webhooks/evolution/{instance_name}
   ```
5. **Não** habilitar ainda o envio em produção — validar com [validation-checklist.md](./validation-checklist.md)

### 2. Desabilitar integração Chatwoot na Evolution

**Obrigatório** antes de ativar o provider nativo — evita mensagens duplicadas.

```http
POST {base_url}/chatwoot/set/{instance_name}
apikey: {api_key}
Content-Type: application/json

{ "enabled": false }
```

Ou via Evolution Manager: desligar integração Chatwoot na instância.

Verificar:

```http
GET {base_url}/chatwoot/find/{instance_name}
```

Resposta deve ter `"enabled": false`.

### 3. Validar paridade (staging)

| Teste | Esperado |
|-------|----------|
| Inbound texto WA → Chatwoot | Uma mensagem no inbox **novo** |
| Outbound agente → WA | Uma mensagem no WhatsApp |
| Inbox legado `api` | **Sem** novas mensagens após passo 2 |
| Echo / duplicata | Nenhuma mensagem em dobro |

### 4. Cutover

1. Desativar ou arquivar inbox legado tipo `api` (ou remover agentes desse inbox)
2. Mover agentes para o inbox `Channel::Whatsapp` evolution
3. Atualizar automações/macros que referenciam o inbox antigo
4. Opcional: renomear inbox novo para o nome operacional anterior

### 5. Limpeza

| Item | Ação |
|------|------|
| Inbox `api` antigo | Deletar após período de observação |
| Webhook CW no Evolution | Permanece `enabled: false` |
| Contatos duplicados | Merge manual ou script — `merge_brazil_contacts` (Fase 2) ajuda em +55 |
| Labels automáticas Evolution | Não portadas — recriar no Chatwoot se necessário |

---

## Cenários especiais

### Mesma instância Evolution, dois inboxes Chatwoot

**Não recomendado.** Um `instance_name` deve mapear a **um** inbox evolution no fork ([decisions.md §3](./decisions.md)). Dois inboxes na mesma instância geram webhook ambíguo.

### Migrar histórico de conversas

A integração legada podia importar via SQL. O provider nativo usa API (Fase 4) — import será **mais lento** e pode não trazer 100% de paridade. Planejar expectativa com o cliente.

### Coexistência temporária (não recomendada)

Se inevitável por rollback:

- Manter **apenas um** caminho ativo por vez (legado **ou** nativo)
- Nunca `chatwoot.enabled: true` na Evolution **e** webhook `/webhooks/evolution/...` ativo simultaneamente

---

## Rollback

1. Desabilitar inbox evolution no Chatwoot (remover agentes)
2. Reabilitar na Evolution:
   ```json
   { "enabled": true, "accountId": "...", "token": "...", "url": "..." }
   ```
3. Restaurar webhook do inbox `api` legado se foi alterado

Documentar credenciais `accountId` / `token` antes do cutover.
