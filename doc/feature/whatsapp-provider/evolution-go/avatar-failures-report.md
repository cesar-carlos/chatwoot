# Relatório — falhas de avatar (Evolution Go)

**Data:** 18/jul/2026 (revalidado 18/jul ~14:25 UTC)  
**Ambiente:** produção (`dev-chat` / account **12** — Frigorifico Santa Rita)  
**Inboxes:** 109, 112, 113, 114, 115 (`provider=evolution_go`)  
**Destinatário:** time Evolution Go / API (correção no provider) + contexto Chatwoot

Este relatório separa o que é **bug/instabilidade da Evolution Go** (ação no provider) do que é **comportamento esperado do WhatsApp** e do que o **Chatwoot já mitigou**.

---

## 0. Pedido à Evolution Go (ação)

| # | Problema | Evidência | Esperado |
|---|----------|-----------|----------|
| **P1** | `POST /user/avatar` hang → `Net::ReadTimeout` no client (12s) | ~3196 logs `user/avatar error` + ~3344 `ReadTimeout` no worker | Responder em &lt; ~5–8s ou erro HTTP claro; não segurar a conexão |
| **P2** | `POST /user/info` / usync → `rate-overlimit` (HTTP 500) sob carga moderada | ~3354 ocorrências `rate-overlimit` no mesmo log | Backoff/429 honesto; não derrubar usync em massa no refresh de perfis |
| **P3** | `/user/info` HTTP 200 **sem** `PictureURL`/`PictureID` enquanto `/user/avatar` com **LID** devolve URL | Anderson `6206` (LID): info vazio; avatar LID → `pps.whatsapp.net` | Info e avatar consistentes para o mesmo JID/LID |
| **P4** | Consulta por telefone BR “sujo” (9º dígito) / dígitos → timeout ou `Users` vazios; JID canônico / `@lid` funciona melhor | Amadeu phone `…9956041` vs JID `…956041@s.whatsapp.net` | Documentar query canônica (preferir `@lid` / PN JID); não hang em dígitos inválidos |

**Não é bug da Go (não corrigir como falha):**

| Caso | Resposta da API | Exemplo |
|------|-----------------|--------|
| Contato sem foto | HTTP 500 `that user or group does not have a profile picture` | PTM 2º Ofício (`6456`) — placeholder **P2** correto |
| Foto oculta | HTTP 500 `the user has hidden their profile picture from you` | ~186 logs; ex. Kátia Mendes `6521` |

---

## 1. Sintoma (Chatwoot)

Na lista de conversas, muitos contatos mostram só iniciais, misturados com contatos que têm foto OK.  
**Não é bug de UI** — `thumbnail` vazio = Active Storage sem avatar.

### Exemplos revalidados (18/jul)

| Contato | ID | Avatar? | Notas |
|---------|----|---------|--------|
| PTM 2º Ofício de Sinop | 6456 | Não | Go: **sem foto de perfil** (esperado) |
| Matheus Sabino | 6463 | Não | Tem `@lid`; sem `picture_id`; último attempt 17/jul |
| Amadeu Rampazzo Junior | 6475 | **Sim** (recuperado) | Antes timeout; tem `picture_id=910972669` |
| Ademir Muller | 5454 | Sim | Caminho feliz (LID + picture_id) |

---

## 2. Métricas (account 12, inboxes Go) — recontagem

| Métrica | Valor (revalidado) | Valor (manhã) |
|---------|--------------------|---------------|
| Contatos ligados a inboxes Go | **2322** | 2321 |
| Com avatar anexado | **1354 (~58%)** | 1257 (~54%) |
| Sem avatar | **968 (~42%)** | 1064 (~46%) |
| Sem avatar + já enriquecidos | **959** | ~1054 |
| Sem avatar + com `evolution_go_picture_id` | **76** | 124 |
| Sem avatar + sem `picture_id` | **892** | 940 |
| Nunca enriquecidos | **9** | ~10 |
| Contatos com `@lid` | **1566** | — |

**Logs worker** (`chatwoot-worker-out.log`, acumulado):

| Padrão | Contagem |
|--------|----------|
| `rate-overlimit` | ~3354 |
| `ReadTimeout` | ~3344 |
| `user/avatar error` | ~3196 |
| `user/avatar failed` | ~831 |
| `hidden their profile picture` | ~186 |
| `does not have a profile picture` | ~29 |

Interpretação:

- A maioria sem foto **já passou** pelo enrichment.
- **76** casos com `picture_id` e sem avatar = WhatsApp conhece a foto, mas o fetch falhou (timeout / rate-limit / query) — **prioridade para a Go**.
- **892** sem `picture_id` misturam: sem foto, privacidade, ou falha antes de gravar ID.

---

## 3. Evidências Evolution Go

### 3.1 `/user/avatar` instável (timeout) — **P1**

```text
[EVOLUTION_GO] user/avatar error for contact 6803:
  Evolution Go API request failed: POST /user/avatar: Net::ReadTimeout with #<TCPSocket:(closed)>
```

- Client Chatwoot: timeout **12s** (`AVATAR_REQUEST_TIMEOUT`); path **non-retryable** (retry dobraria a espera).
- Contatos afetados (amostra): 6900, 7324, 7336, 7107, 6803, 6475 (antes da recuperação), etc.

### 3.2 Usync `rate-overlimit` — **P2**

```text
[EVOLUTION_GO] user/info failed for contact 7266: HTTP 500
  failed to send usync query: info query returned status 429: rate-overlimit
```

Sob refresh em massa / muitos enrichments, a Go devolve HTTP 500 com mensagem de rate-limit. O Chatwoot evita carimbar cooldown longo nesses casos, mas o perfil/avatar não atualiza.

### 3.3 `/user/info` sem `PictureURL` com foto existente — **P3**

Probe Anderson (`6206`, `identifier=…@lid`):

| Chamada | Resultado |
|---------|-----------|
| `POST /user/info` com LID | HTTP 200, `Users` vazio / sem `PictureURL` |
| `POST /user/avatar` com **LID** | HTTP 200 + URL `https://pps.whatsapp.net/...` + `id` |

A foto **existe**; `/user/info` nem sempre a devolve; `/user/avatar` com LID funciona quando a Go responde a tempo.

### 3.4 Telefone BR vs JID / LID — **P4**

Amadeu:

- `phone_number`: `+5566999956041` (9º dígito extra)
- `evolution_go_remote_jid`: `556699956041@s.whatsapp.net`

Dígitos “sujos” → timeout / payload vazio. Preferir **`@lid`** ou PN JID canônico.

### 3.5 Controle — sem foto (não é bug)

**PTM** (`6456`), probe 18/jul ~14:20 UTC:

| Chamada | Resultado |
|---------|-----------|
| `POST /user/info` JID | HTTP 200, `Users` presente mas `PictureID`/`PictureURL`/LID vazios |
| `POST /user/avatar` JID | HTTP 500 `that user or group does not have a profile picture` |
| `POST /user/avatar` dígitos | `Net::ReadTimeout` (~12s+) |

Conclusão: Sync/Chatwoot **não consegue** inventar avatar; placeholder **P2** está correto. O timeout no fallback por dígitos ainda é ruído (**P1/P4**).

---

## 4. Mitigações Chatwoot (já aplicadas — não bloqueiam correção na Go)

1. Query avatar **LID → PN JID → dígitos do JID** (não prioriza phone BR).
2. Timeout de rede → `evolution_go_avatar_timeout_at` (**30 min**), não cooldown 6h.
3. Cooldown 6h só para sem-foto / privacidade (HTTP sem URL).
4. `finalize_avatar_miss!` só após esgotar candidatos.
5. Sync forçado: até 3 retries em timeout, todos candidatos, download CDN inline, requeue se lock busy.

Mitigação **não elimina** P1–P4; só reduz impacto no Sidekiq e melhora taxa de sucesso quando a Go responde.

Operador: menu ⋮ → **Sync contact info** (`force: true`) ou Refresh na settings da inbox.

---

## 5. Caso contraste (OK)

Ademir Muller (`5454`): avatar anexado, `evolution_go_picture_id` + `last_avatar_sync_at`, identifier `@lid` — caminho feliz.

---

## 6. Como reproduzir (para o time da API)

1. Instância Evolution Go das inboxes 109–115 (account 12).
2. `POST /user/avatar` com `apikey` = instance token:
   - Contato com foto conhecida + `@lid` (ex. Anderson) — validar latência e URL.
   - Contato PTM `5565993597528@s.whatsapp.net` — deve retornar erro “no profile picture” sem hang.
   - Mesmo número só com dígitos — hoje costuma **timeout** (bug).
3. `POST /user/info` com LID vs PN JID vs dígitos BR com 9º extra — comparar `PictureURL`/`PictureID`.
4. Sob carga (dezenas de `/user/info` + `/user/avatar`): observar `rate-overlimit`.
5. Logs Chatwoot: `rg "user/avatar error|rate-overlimit" ~/.pm2/logs/chatwoot-worker-out.log`.

---

## 7. Atribuição

| Responsável | Problema |
|-------------|----------|
| **Evolution Go (corrigir)** | P1 timeout `/user/avatar`; P2 `rate-overlimit`; P3 info sem PictureURL; P4 hang/vazio em query por dígitos BR |
| **WhatsApp / privacidade (esperado)** | Sem foto; foto oculta |
| **Chatwoot (mitigado)** | Query por telefone; cooldown 6h após timeout → LID-first + timeout 30m + Sync resiliente |

---

## 8. Referências

- Código: `custom/app/services/custom/whatsapp/evolution_go/contact_enrichment_service.rb`
- Client timeout: `custom/app/services/custom/whatsapp/evolution_go/api_client.rb` (`AVATAR_REQUEST_TIMEOUT=12`)
- Specs: `spec/custom/services/custom/whatsapp/evolution_go/contact_enrichment_service_spec.rb`
- ADR: [decisions.md](./decisions.md) §36 addendum 18/jul
- Troubleshooting: [troubleshooting.md](./troubleshooting.md)
