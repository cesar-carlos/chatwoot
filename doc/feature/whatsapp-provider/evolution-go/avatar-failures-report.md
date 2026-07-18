# Relatório — falhas de avatar (Evolution Go)

**Data:** 18/jul/2026  
**Ambiente:** produção (`dev-chat` / account **12** — Frigorifico Santa Rita)  
**Inboxes:** 109, 112, 113, 114, 115 (`provider=evolution_go`)

Este relatório separa o que é **limitação/instabilidade da Evolution Go** do que era **gap no enrichment Chatwoot**, e registra a mitigação aplicada no fork.

---

## 1. Sintoma

Na lista de conversas, muitos contatos mostram apenas iniciais (sem foto), misturados com contatos que têm avatar OK.

API Chatwoot (exemplo conversa `136` / contact `6475`):

```json
{
  "id": 6475,
  "name": "Amadeu Rampazzo Junior",
  "thumbnail": "",
  "additional_attributes": {
    "evolution_go_picture_id": "910972669",
    "evolution_go_remote_jid": "556699956041@s.whatsapp.net",
    "evolution_go_enriched_at": "2026-07-18T13:24:53.668Z",
    "evolution_go_avatar_attempted_at": "2026-07-18T13:24:53.639Z"
  }
}
```

Conclusão imediata: **não é bug de UI** — o Active Storage não tem avatar anexado (`thumbnail` vazio).

---

## 2. Métricas (account 12, inboxes Go)

| Métrica | Valor |
|---------|-------|
| Contatos ligados a inboxes Go | 2321 |
| Com avatar anexado | 1257 (~54%) |
| Sem avatar | 1064 (~46%) |
| Sem avatar + já enriquecidos | ~1054 |
| Sem avatar + com `evolution_go_picture_id` | 124 |
| Sem avatar + sem `picture_id` | 940 |
| Nunca enriquecidos | ~10 |
| Ocorrências log `user/avatar` / `ReadTimeout` (worker) | ~3800+ |

Interpretação:

- A maioria sem foto **já passou** pelo enrichment.
- 124 casos têm `picture_id` (WhatsApp conhece a foto) mas o Chatwoot não anexou — forte sinal de falha no fetch `/user/avatar`, não de “contato sem foto”.
- 940 sem `picture_id` misturam: privacidade, timeout antes de gravar ID, ou foto realmente ausente.

---

## 3. Evidências Evolution Go

### 3.1 `/user/avatar` instável (timeout)

Logs Sidekiq (mesmo dia):

```text
[EVOLUTION_GO] user/avatar error for contact 6475:
  Evolution Go API request failed: POST /user/avatar: Net::ReadTimeout
```

Timeout configurado no client: **12s** (`ApiClient::AVATAR_REQUEST_TIMEOUT`). Path é **non-retryable**.

Afeta Amadeu (`6475`), Anderson (`6206`), Luciano (`6915`), Pretaah (`6900`), etc.

### 3.2 `/user/info` frequentemente sem `PictureURL`

Probe Anderson (`6206`, `identifier=…@lid`):

| Chamada | Resultado |
|---------|-----------|
| `POST /user/info` com LID | HTTP 200, `Users` vazio / sem `PictureURL` |
| `POST /user/avatar` com **LID** | HTTP 200 + URL `https://pps.whatsapp.net/...` + `id` = picture_id |

Ou seja: a foto **existe no WhatsApp**; o path `/user/info` nem sempre a devolve; `/user/avatar` com LID funciona quando a Go responde a tempo.

### 3.3 Divergência telefone BR vs JID

Amadeu:

- `phone_number`: `+5566999956041` (com 9º dígito extra típico BR)
- `evolution_go_remote_jid`: `556699956041@s.whatsapp.net`

Consultas com o phone “sujo” tendem a timeout / `Users` vazios. O enrichment já evita inventar `phone@s.whatsapp.net` no `/user/info`; o gap era no **avatar** (ver §4).

---

## 4. Gap Chatwoot (corrigido 18/jul/2026)

Antes:

- `/user/info` usava LID → JID → dígitos (`user_info_query`).
- `/user/avatar` usava `lookup_number` → **telefone primeiro**.
- Em `Net::ReadTimeout`, marcava `evolution_go_avatar_attempted_at` → **cooldown 6h**, bloqueando retries no inbound.

Depois (`ContactEnrichmentService`):

1. **`avatar_query_candidates`**: LID → `@s.whatsapp.net` → dígitos do JID (não prioriza phone BR).
2. **Um fallback** se a 1ª query falhar (timeout / vazio).
3. **Timeout de rede não marca cooldown 6h** (transitório, como rate-limit). Cooldown 6h permanece para “sem foto” / privacidade (HTTP sem URL).

Operador pode forçar reprocessamento: menu ⋮ → **Sync contact info** (`force: true`) ou Refresh na settings da inbox.

---

## 5. Caso contraste (OK)

Ademir Muller (`5454`): avatar anexado, `thumbnail` Active Storage, `evolution_go_picture_id` + `last_avatar_sync_at` presentes — caminho feliz quando Go devolve URL a tempo e o query acerta.

---

## 6. Como reproduzir

1. Contato sem avatar na account 12:  
   `GET /api/v1/accounts/12/contacts/:id` → `thumbnail` vazio; checar `evolution_go_*`.
2. Via `ApiClient` / curl Evolution Go (`apikey` = instance token):
   - `POST /user/info` com `identifier` `@lid` e com PN JID.
   - `POST /user/avatar` com LID vs dígitos do phone.
3. Worker: `rg "user/avatar error for contact" ~/.pm2/logs/chatwoot-worker-out.log`.

---

## 7. Atribuição

| Responsável | Problema |
|-------------|----------|
| **Evolution Go / WhatsApp usync** | Timeouts em `/user/avatar`; `/user/info` sem `PictureURL` mesmo com foto existente |
| **Chatwoot (mitigado)** | Avatar query por telefone; cooldown 6h após timeout |

Mitigação Chatwoot **não elimina** timeouts da Go; reduz falhas por query errada e permite retry mais cedo após timeout.

---

## 8. Referências

- Código: `custom/app/services/custom/whatsapp/evolution_go/contact_enrichment_service.rb`
- Specs: `spec/custom/services/custom/whatsapp/evolution_go/contact_enrichment_service_spec.rb`
- ADR: [decisions.md](./decisions.md) §36 addendum 18/jul
- Troubleshooting: [troubleshooting.md](./troubleshooting.md)
