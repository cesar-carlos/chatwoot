# Message Forward — Improvements backlog

Pós-MVP. Não bloqueia o uso atual.

---

## Já no MVP

- Pseudo-forward texto + anexos
- Modal recentes + busca + multi-select (máx. 5)
- Badge dashboard `forwarded`
- Gate Evolution Go + Node
- Toasts sucesso/parcial/falha
- Docs ADR §34 + pasta `doc/feature/message-forward/`

---

## P1 — Alto valor / baixo risco

| ID | Item | Notas |
|----|------|-------|
| F-P1-1 | Caption opcional no modal | Campo texto enviado junto com mídia |
| F-P1-2 | Toast com link “Open conversation” quando 1 destino | Sem mudar default de ficar na conversa |
| F-P1-3 | Retry só nos destinos que falharam | UI: botão no toast / reabrir modal pré-selecionado |
| F-P1-4 | Melhor nome de arquivo no re-fetch | Usar `filename` / blob metadata se disponível |
| F-P1-5 | Spec Vitest do composable | `fetchAttachmentFiles`, `recentConversationsForInbox`, merge de resultados |

---

## P2 — Produto / UX maior

| ID | Item | Notas |
|----|------|-------|
| F-P2-1 | Multi-select de mensagens na timeline | Barra “Forward” estilo WhatsApp Web |
| F-P2-2 | Encaminhar para outros canais do mesmo account | Regras por channel_type |
| F-P2-3 | Prefetch / cache de blobs | Evitar re-download se encaminhar de novo |
| F-P2-4 | Endpoint server-side clone | **Parcial (28/jul/2026):** clone via `attachment_ids` no `messages#create` + `AttachmentCloneService`. Residual: anexos sem id / URL externa cross-origin (Instagram, S3 direto). Alias-host AS também coberto por `toSameOriginActiveStorageUrl` no fallback fetch |

---

## P3 — Depende de Evolution Go upstream

| ID | Item | Bloqueio |
|----|------|----------|
| F-P3-1 | Soft-forward `forwarded: true` nos `/send/*` | API Go |
| F-P3-2 | `POST /message/forward` por message key | API Go |
| F-P3-3 | Badge inbound `contextInfo.isForwarded` | Confirmar payload webhook |

---

## Explicitamente fora

- i18n pt/pt_BR (community)
- Forward cross-account
- Modelo nativo OSS Chatwoot de “forward” independente de canal

---

*Última atualização: 28/jul/2026*
