# Adaptação das regras — Evolution legado → provider nativo Chatwoot

Avaliação de **cada regra** da integração Evolution (`chatwoot.service.ts`, `ChatwootDto`, settings Baileys, proxy) para o contexto deste fork: inbox **`Channel::Whatsapp`** nativo, sem `/chatwoot/set`, sem inbox API, sem SQL de import.

**Catálogo técnico:** [inbox-business-rules.md](./inbox-business-rules.md) · **Telas Manager:** [§ Checklist UI](./inbox-business-rules.md#checklist--paridade-com-ui-evolution-manager)

---

## Contexto do fork (por que não copiar a Evolution)

| Evolution legado | Nossa realidade |
|------------------|-----------------|
| Inbox tipo `api` + SDK `@figuro/chatwoot-sdk` | `Channel::Whatsapp` — pipeline upstream de mensagens/conversas |
| Evolution cria inbox/conta via `autoCreate` | Wizard Chatwoot cria inbox |
| Bot contato `123456` + QR como imagem | Wizard + ActionCable; agentes reais no CW |
| `organization` / `logo` no bot Evolution | Branding Chatwoot (`useBranding`) |
| Import via **SQL** no Postgres CW | Fase 4 só via API (`findContacts` / `findMessages`) |
| `CHATWOOT_MESSAGE_READ/DELETE` globais no `.env` Evolution | Campos por inbox em `provider_config` |
| Assinatura `*agente:*` comum (Manager default ON) | UI CW já mostra autor — assinatura **opcional**, default **OFF** |
| Proxy só em settings avançados | Self-host BR: proxy **no wizard** (opcional) — muitos operadores já usam |

**Princípio:** portar **comportamento útil**, não **mecanismo legado**. Onde o Chatwoot já resolve melhor, usar upstream e não duplicar.

---

## Matriz de adaptação (todas as regras)

Legenda **Decisão fork:**

| Código | Significado |
|--------|-------------|
| ✅ **Portar** | Implementar equivalente no `custom/` |
| ⚙️ **Adaptar** | Portar com default ou lógica diferente |
| 🔧 **CW nativo** | Deixar comportamento padrão Chatwoot (sem campo Evolution) |
| ❌ **Não portar** | Específico da integração legada |
| 📅 Fase | Quando implementar |

### Conexão e proxy

| Regra (Manager / código) | Evolution | **Default fork** | Decisão | Fase | Notas |
|--------------------------|-----------|------------------|---------|------|-------|
| **Proxy** (host, port, protocol, auth) | `POST /proxy/set` | `proxy_enabled: false` | ⚙️ Portar | **1** (wizard opcional) + settings | Operadores com ban/IP fixo precisam antes do QR. Seção colapsável no wizard; `sync_proxy!` no create. |
| `base_url`, `api_key` (`AUTHENTICATION_API_KEY` global), `instance_name` | create/connect | obrigatório | ✅ | 1 | — |
| Desabilitar integração CW na Evolution | `chatwoot.enabled` | sempre `false` | ✅ | 1 | [decisions.md §7](./decisions.md) |

### Settings Baileys (`POST /settings/set`)

| Regra | Evolution (Manager) | **Default fork** | Decisão | Fase | Notas |
|-------|---------------------|------------------|---------|------|-------|
| **Ignore Groups** | OFF no screenshot | **`true`** | ⚙️ | 1 | Suporte 1:1; grupos geram ruído. Hardcoded F1 + toggle F2. |
| **Reject Calls** | OFF | **`false`** | ⚙️ | 2 | Útil em BR; ativar com `msg_call` opcional. |
| `msg_call` | `""` | `""` | ⚙️ | 2 | Só se `reject_call: true`. |
| **Always Online** | OFF | **`false`** | ⚙️ | 2 | Risco detecção; opt-in consciente. |
| **Read Messages** | OFF | **`false`** | ⚙️ | 2 | Blue tick sem agente ler — polêmico para CSAT. |
| **Read Status** | OFF | **`false`** | ⚙️ | 3 | Stories; baixa prioridade. |
| **Sync Full History** | OFF | **`false`** | ⚙️ | 3 | Pesado; conflita com import Fase 4. |

### Integração Chatwoot legada → conversas

| Regra | Evolution (Manager) | **Default fork** | Decisão | Fase | Notas |
|-------|---------------------|------------------|---------|------|-------|
| **Reopen Conversation** | ON | **`true`** | ⚙️ | 1 | Alinhado ao CW: mensagem em conversa resolvida deve reabrir. Usar `Conversation` callbacks / builder fork, não SDK. |
| **Conversation Pending** | OFF | **`false`** | ⚙️ | 2 | CW default: conversa nova **open**. Pending só se operação exigir triagem. |
| **Merge Brazil Contacts** | API default `false`, doc sugere `true` | **`true`** | ⚙️ | 2 | Fork BR: unificar +55 com/sem 9º dígito no normalizer/`ContactInboxBuilder`. |

### Outbound agente

| Regra | Evolution | **Default fork** | Decisão | Fase | Notas |
|-------|-----------|------------------|---------|------|-------|
| **Sign Messages** | Manager ON | **`false`** | ⚙️ | 2 | CW já exibe nome do agente; evitar `*João:*` duplicado no WhatsApp. |
| `sign_delimiter` | `\n` | `\n` | ⚙️ | 2 | Só se `sign_msg: true`. |
| `send_templates_as_text` | template → texto | **`true`** | ✅ | 1 | Baileys sem WABA; obrigatório. |
| `convert_markdown_outbound` | `*→_`, `**→*` | **`true`** | ⚙️ | 2 | CW markdown ≠ WA formatting. |
| `convert_markdown_inbound` | inverso | **`true`** | ⚙️ | 2 | Normalizer. |
| `send_random_delay` | 500–2000 ms | **`true`** | ⚙️ | 2 | Anti-ban leve no outbound. |
| `mark_read_on_reply` | env `CHATWOOT_MESSAGE_READ` | **`false`** | ⚙️ | 2 | Privacidade; opt-in. |
| `notify_send_errors_private` | `onSendMessageError` | **`true`** | ✅ | 2 | Nota privada ao falhar envio — boa UX operação. |
| `sync_delete_to_whatsapp` | env `CHATWOOT_MESSAGE_DELETE` | **`false`** | ⚙️ | 3 | Deletar no WA é irreversível; opt-in. |

### Inbound / filtros

| Regra | Evolution | **Default fork** | Decisão | Fase | Notas |
|-------|-----------|------------------|---------|------|-------|
| **Ignore Jids** | tags, ex. `@g.us` | **`["@g.us"]`** | ⚙️ | 1 (default) / 2 (UI) | Redundante com `groups_ignore` — defesa em profundidade. |
| `ignore_status_broadcast` | implícito | **`true`** | ✅ | 1 | Hardcoded normalizer. |
| `ignore_from_me_echo` | implícito | **`false`** | ✅ | 1 | Default `false` — permite sync de msgs enviadas pelo celular. |
| `ignore_survey_links` | `/survey/responses/` | **`true`** | ⚙️ | 2 | CSAT CW ecoando no WA. |
| `ignore_private_notes` | `receiveWebhook` | 🔧 **CW nativo** | — | Notas privadas já não disparam `SendOnWhatsappService`. |
| `format_group_messages` | prefixo participante | **`false`** | ⚙️ | 3 | Grupos fora do escopo MVP; se habilitar grupos no futuro. |

### Import histórico

| Regra | Evolution Manager | API create | **Default fork** | Decisão | Fase |
|-------|-------------------|------------|------------------|---------|------|
| **Import Contacts** | OFF | `true` | **`false`** | ⚙️ | 4 | Pesado; opt-in pós-conexão. |
| **Import Messages** | OFF | `true` | **`false`** | ⚙️ | 4 | API rate-limited; sem SQL. |
| **Days Limit** | **7** | **60** | **`7`** | ⚙️ | 4 | Seguir Manager (operador), não API. |

### Regras legado — não portar

| Regra Evolution | Motivo |
|-----------------|--------|
| `autoCreate` | Inbox criado pelo wizard Chatwoot |
| `accountId`, `token`, `url` (Chatwoot na Evolution) | Chatwoot **é** o host |
| `organization`, `logo` (bot) | Branding CW |
| Bot `123456` / `CHATWOOT_BOT_CONTACT` | Wizard QR |
| `WAID:` prefix `source_id` | `key.id` Baileys |
| `chatwoot-import-helper` SQL | Proibido no fork |
| `syncLostMessages` cron 30 min | Opcional futuro; não MVP |
| Labels automáticas por `nameInbox` | Labels CW manuais/automações |
| `webhookUrl` `/chatwoot/webhook/` | `/webhooks/evolution/:instance` |

---

## Proxy — decisão de negócio (incluir na Fase 1)

### Por que não esperar Fase 2

| Fator | Impacto |
|-------|---------|
| Self-hosted + Baileys | Ban por IP de datacenter é comum |
| QR falha sem rota estável | Operador configura proxy **antes** de escanear |
| Evolution valida no set | Falha cedo com mensagem clara (`Invalid proxy`) |
| Independente de mensagens | Não depende de mídia/status |

### UX wizard (Fase 1)

```
Step 1 — Conexão
  ├── base_url, api_key, instance_name (obrigatório)
  └── [▼] Proxy (opcional)
        ├── proxy_enabled
        ├── host, port, protocol
        └── username, password

Step 2 — QR
```

Se `proxy_enabled` no create:

1. `POST /instance/create` com `proxyHost`… **ou** create sem proxy → `POST /proxy/set` imediato
2. Se 400 `Invalid proxy` → bloquear avanço ao QR com erro na UI
3. Após mudança de proxy em settings → sugerir **restart** instância

### O que não replicar

- Lista rotativa `proxyscrape` no host (`baileys.service.ts`) — comportamento legado Evolution; operador informa proxy fixo.

---

## Conversas — adaptar ao Chatwoot upstream

### Reabrir conversa resolvida (Fase 1)

Evolution reutiliza conversa mesmo `resolved`. No fork, usar o mecanismo nativo **`inbox.lock_to_single_conversation`** (Settings → Roteamento de conversas) — **não** duplicar em `provider_config`.

```ruby
# Conversations::Resolver#find_conversation (fork)
return contact_inbox.conversations.order(created_at: :desc).first if inbox.lock_to_single_conversation?

# Message#reopen_conversation (after_create_commit) — reabre resolved no inbound
```

Se `conversation_pending: true` (Fase 2): prepend `Custom::Message` chama `conversation.pending!` em vez de `open!` ao reabrir.

**Métricas:** com `lock_to_single_conversation` + `conversation_pending` ON, `Custom::Conversations::ResolutionCycle` considera `evolution_pending_since` como candidato a início de ciclo (além de `conversation_opened` e `created_at`).

### `merge_brazil_contacts: true` (Fase 2)

Portar lógica `mergeBrazilianContacts` (~499) no `ContactInboxBuilder` ou normalizer — normalizar `5511` vs `5511987654321` antes de lookup.

---

## `provider_config` — defaults oficiais do fork

Substitui o JSON de referência em [inbox-business-rules.md](./inbox-business-rules.md). Usar na factory/seeds e no wizard.

```json
{
  "groups_ignore": true,
  "reject_call": false,
  "msg_call": "",
  "always_online": false,
  "read_messages": false,
  "read_status": false,
  "sync_full_history": false,

  "proxy_enabled": false,
  "proxy_host": "",
  "proxy_port": "",
  "proxy_protocol": "http",
  "proxy_username": "",
  "proxy_password": "",

  "sign_msg": false,
  "sign_delimiter": "\n",
  "conversation_pending": false,
  "merge_brazil_contacts": true,

  "mark_read_on_reply": false,
  "sync_delete_to_whatsapp": false,
  "convert_markdown_outbound": true,
  "convert_markdown_inbound": true,
  "send_templates_as_text": true,
  "send_random_delay": true,
  "notify_send_errors_private": true,

  "ignore_jids": ["@g.us"],
  "ignore_status_broadcast": true,
  "ignore_from_me_echo": false,
  "ignore_survey_links": true,

  "import_contacts": false,
  "import_messages": false,
  "days_limit_import_messages": 7
}
```

---

## Fases revisadas (com proxy + regras essenciais)

| Fase | Entregas de regras |
|------|-------------------|
| **1** | Conexão, proxy opcional wizard, `groups_ignore`, filtros hardcoded, `lock_to_single_conversation`, `send_templates_as_text`, bypass 24h |
| **2** | Settings UI completa, `sign_msg`, markdown, delay, merge BR, ignore_jids UI, reject_call, read_messages, mark_read_on_reply, erros privados, mídia |
| **3** | sync_delete, read_status, sync_full_history, grupos (se produto) |
| **4** | import_* via API |

---

## Checklist implementação

- [ ] Wizard aplica JSON defaults acima no `provider_config`
- [ ] `ConnectionService` aplica proxy + settings no create (não só no PATCH settings)
- [ ] `lock_to_single_conversation` na criação/reabertura de conversa inbound
- [ ] Nunca persistir `chatwootAccountId` / token Evolution no channel
- [ ] Documentar para operador: defaults diferem do Manager Evolution (tabela acima)
