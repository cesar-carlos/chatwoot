# Adaptação de regras de negócio — Z-API

Como as regras padrão do Chatwoot WhatsApp se aplicam ao provider `zapi`.

---

## Janela de 24 horas

| Regra oficial | Comportamento `zapi` |
|---------------|----------------------|
| Bloqueio após 24h sem resposta | **Desabilitado** — sessão livre (não-oficial) |
| Implementação | prepend `MessageWindowService` + capability `unlimited_session` |

Igual Evolution — reusar o mesmo prepend com guard `provider == 'zapi'`.

---

## Templates

| Regra | Comportamento |
|-------|---------------|
| `sync_templates` | noop |
| Template picker UI | ocultar |
| Campanhas com template | não suportado |

Z-API não expõe templates WABA da Meta Cloud API.

---

## Contatos

| Regra | Comportamento |
|-------|---------------|
| `merge_brazil_contacts` | `true` — normalizar `55` + DDD |
| `source_id` | `phone` do payload (só dígitos) |
| LID | fallback `senderLid` se necessário — [doc LID](https://developer.z-api.io/tips/lid.md) |
| Nome contato | `senderName` / `chatName` do webhook |

---

## Conversas

| Regra | Default |
|-------|---------|
| `lock_to_single_conversation` | `true` |
| Reabrir ao receber mensagem | comportamento padrão Chatwoot |
| Grupos | **não criar** conversa se `isGroup: true` |
| Canais (`isNewsletter`) | ignorar MVP |

---

## Mensagens

| Regra | Comportamento |
|-------|---------------|
| `sign_msg` | `false` — irrelevante para Z-API |
| Echo outbound | ignorar `fromMe: true` |
| `source_id` outbound | `messageId` do POST send-text |
| Status | mapear `SENT`, `RECEIVED`, `READ`, `PLAYED` |
| Mídia inbound | download imediato — URL expira ~30 dias |
| Reply | `messageId` no send quando Fase 2 |

---

## Inbox settings recomendados

```json
{
  "ignore_groups": true,
  "notify_sent_by_me": false,
  "auto_read": false
}
```

Não ativar `update-auto-read-message` na Z-API — conflita com controle manual do agente.

---

## Features cloud-only a ocultar

- Template messages / campanhas HSM
- WhatsApp Business profile sync
- Phone number quality rating
- 360dialog / embedded signup

---

## Compliance e risco

| Tema | Nota |
|------|------|
| API não oficial | Mesmo perfil de risco que Evolution — ver [official-vs-unofficial-restrictions.md](../official-vs-unofficial-restrictions.md) |
| Rate limit | Sem limite declarado Z-API — risco ban WhatsApp por volume |
| Boas práticas | [best-practices](https://developer.z-api.io/tips/best-practices.md) |
