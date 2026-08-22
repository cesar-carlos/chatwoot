# Message Forward — Improvements backlog

Pós-MVP. Não bloqueia o uso atual.

---

## Já no MVP

- Pseudo-forward texto + anexos
- Modal recentes + busca + multi-select de destinos (máx. 5)
- Multi-select de mensagens na timeline (máx. 10) + barra de ação
- Checkbox do design system (timeline e destinos); sem hover fantasma
- Modal `xl`; Dialog `max-h-[90vh]`; só a lista de contatos rola; footer fixo
- Busca alinhada (lupa + input no mesmo outline; `type="text"`)
- Tailwind `content` inclui `custom/app/javascript/**`
- Shift+clique para intervalo; modo Select só sai no ✕ / Escape / sucesso
- Toast Open conversation (1 destino) + Retry no modal
- Caption editável enviado com o forward
- Clone server-side via `attachment_ids` + `forwarded_from_message_id`
- Badge dashboard `forwarded`
- Gate Evolution Go + Node
- Toasts sucesso/parcial/falha (EN + pt_BR, inclusive `FORWARD.ERRORS.*`)
- Docs ADR §34 + pasta `doc/feature/message-forward/`

---

## P1 — Alto valor / baixo risco

| ID | Item | Notas |
|----|------|-------|
| F-P1-1 | Caption opcional no modal | ✅ Entregue — textarea `CAPTION_*` + `contentOverride` |
| F-P1-2 | Toast com link “Open conversation” quando 1 destino | ✅ Entregue — `useAlert` + `action.type: link`; agente fica na conversa se não clicar |
| F-P1-3 | Retry só nos destinos que falharam | ✅ Entregue — modal re-seleciona falhas e o confirm vira `RETRY` |
| F-P1-4 | Melhor nome de arquivo no re-fetch | ✅ Entregue — `attachmentFileName` usa `filename` / blob / URL |
| F-P1-5 | Spec Vitest do composable | `fetchAttachmentFiles`, `recentConversationsForInbox`, merge de resultados |

---

## P2 — Produto / UX maior

| ID | Item | Notas |
|----|------|-------|
| F-P2-1 | Multi-select de mensagens na timeline | ✅ Entregue — context menu **Select**, barra, até 10 msgs, envio em ordem |
| F-P2-5 | Polish UI do modo Select + modal | ✅ Entregue — `Checkbox` design system, inset da borda, modal `xl`, Dialog `max-h-[90vh]` + lista `flex-1 overflow-y-auto`, busca `type="text"` com outline no wrapper, Tailwind scan `custom/`, Cancelar ícone-only, tooltip Shift, badges Aberta/Pendente, progresso por destino |
| F-P2-2 | Encaminhar para outros canais do mesmo account | Regras por channel_type |
| F-P2-3 | Prefetch / cache de blobs | Evitar re-download se encaminhar de novo |
| F-P2-4 | Endpoint server-side clone | **Parcial:** clone via `attachment_ids` no `messages#create` + `AttachmentCloneService` (exige `forwarded_from_message_id`). Residual: anexos sem id / URL externa cross-origin (Instagram, S3 direto). Alias-host AS também coberto por `toSameOriginActiveStorageUrl` no fallback fetch |

---

## P3 — Depende de Evolution Go upstream

| ID | Item | Bloqueio |
|----|------|----------|
| F-P3-1 | Soft-forward `forwarded: true` nos `/send/*` | API Go |
| F-P3-2 | `POST /message/forward` por message key | API Go |
| F-P3-3 | Badge inbound `contextInfo.isForwarded` | Confirmar payload webhook |

---

## Explicitamente fora

- i18n de community locales (além de EN / pt_BR)
- Forward cross-account
- Modelo nativo OSS Chatwoot de “forward” independente de canal

---

*Última atualização: 22/ago/2026*
