# Automation `opened_by` — Backlog de melhorias

## Feito

- [x] Persistência `opened_by` em `additional_attributes`
- [x] Stamp create (`contact` / `agent` / `phone`), incluindo Wavoip/voz
- [x] Stamp reopen (incoming, Reabrir, resposta outgoing do agente, compose)
- [x] Ciclo Evolution `conversation_pending` preserva `contact`
- [x] Condição de Automação em created + opened
- [x] i18n en + pt_BR
- [x] Specs custom
- [x] Limpar `Current` no inbound WhatsApp
- [x] Widget e API pública de create gravam `opened_by=contact`
- [x] Resposta do contato não regrava `phone`/`agent` num episódio que ainda está `pending`
- [x] Create do agente ignora `opened_by` enviado pelo cliente
- [x] Canais incoming gravam `contact` (e `phone` no echo de Instagram, Facebook e TikTok; `agent` no Twitter da própria conta)
- [x] Histórico único: mensagem do celular em resolved/snoozed reabre como `phone`
- [x] Condição também em `message_created` e nas regras de fluxo
- [x] Filtro **Aberto por** na lista
- [x] Backfill explícito (`opened_by:backfill`)
- [x] Contagem no relatório ao vivo

---

## P1 — Próximo

| Item | Notas |
|------|-------|
| Smoke nas contas que usam o menu | Confirmar a condição **Aberto por = Contato** nas regras Criada e Aberta. Não alterar regras já salvas automaticamente |

---

## Fora de escopo

- Unificar `agent` + `phone` num único valor `origin` (quebraria regras já salvas)
- Alterar regras existentes no banco automaticamente
- Delayed automations com `opened_by` (o re-check não reconstrói o episódio; a allowlist segue `status` + `inbox_id`)
- Inventar `contact` na leitura de conversas sem stamp
