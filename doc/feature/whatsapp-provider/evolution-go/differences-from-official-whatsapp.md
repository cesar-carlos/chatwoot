# Diferenças vs WhatsApp Cloud API oficial — `evolution_go`

Provider `evolution_go` usa **whatsmeow** (WhatsApp Web) — não Graph API / WABA.

**Contexto geral:** [../official-vs-unofficial-restrictions.md](../official-vs-unofficial-restrictions.md)

---

## O que deixa de existir (Meta)

| Feature Cloud | `evolution_go` | Ação fork |
|---------------|----------------|-----------|
| Janela 24h Meta | Não existe | Prepend `MessageWindowService` → `nil` |
| Templates WABA | Não existe | `sync_templates` noop; texto livre |
| Embedded signup | Não existe | Wizard QR/pairing |
| `phone_number_id` / WABA IDs | Não existe | `instance_name` + tokens |
| HMAC webhook Meta | Não existe | `?token=webhook_token` |
| Calling API Meta | Não existe | Projeto voz separado |
| Campanhas / CSAT cloud | Cloud only | Indisponível |
| Health Meta | Cloud only | `GET /instance/status` |

---

## O que o Chatwoot ainda impõe (bypass)

Mesmas mitigações de qualquer gateway — ver [../gaps-and-blockers.md](../gaps-and-blockers.md):

| Bloqueio | Mitigação |
|----------|-----------|
| `PROVIDERS` whitelist | `# FORK:` + `evolution_go` |
| Janela 24h CW | prepend `MessageWindowService` |
| `process_response` Meta format | `data.Info.ID` em `EvolutionGoService` |
| Frontend cloud-only UI | `isEvolutionGoWhatsAppChannel` |

---

## Específico Evolution Go vs Evolution API Node

| Aspecto | `evolution` (Node) | `evolution_go` |
|---------|-------------------|----------------|
| Protocolo | Baileys | whatsmeow |
| Integração CW nativa na Evolution | existe (`/chatwoot/set`) | **não existe** |
| Webhook auth body | `apikey` | `?token=` apenas |
| Send path | `/message/sendText/:instance` | `/send/text` |
| Outbound ID | `key.id` | `data.Info.ID` |
| Licença servidor | v2.4+ opcional | Magic Link obrigatório |
| PostgreSQL | opcional | **obrigatório** |

---

## O que ganha

| Benefício | Notas |
|-----------|-------|
| Texto livre anytime | Motivador principal |
| Performance Go | Menor memória vs Node |
| Self-host | Docker `evoapicloud/evolution-go` |
| Proxy no create | Objeto `proxy` inline |

---

## Riscos que permanecem

| Risco | Mitigação |
|-------|-----------|
| Ban WhatsApp / ToS | Operacional — não técnico |
| Instabilidade sessão | Reconnect + alertas `CONNECTION` |
| Licença Go expirada | Monitorar painel Evolution |
| Sem suporte Meta | SLA próprio |

---

## UI — o que não prometer

- Templates aprovados Meta
- Quality rating / WABA health
- Chamadas nativas no mesmo inbox
- Coexistence / SMB echoes
- Campanhas one-off cloud
