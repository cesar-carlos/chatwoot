# Share Contact Card — Plano de Implementação

Registro do que foi entregue no fork. O comportamento atual está em [current-state.md](./current-state.md).

**Atualizado out/2026.** Fases 1 a 4 e os gateways Evolution / Evolution Go estão implementados.

---

## Objetivo entregue

1. O agente compartilha um contato do CRM em WhatsApp Cloud, 360dialog, Evolution, Evolution Go e Telegram.
2. Atalho de um clique para o contato da conversa, quando ele tem telefone.
3. O cliente recebe o cartão nativo. O thread usa `Contact.vue`.
4. i18n `en` + `pt_BR`.
5. Handler e gateways em `custom/`; marcas `# FORK:` só nos pontos de entrada do core.

---

## Fase 1 — Backend

- [x] `shared_contact_id` cria attachment `contact` com telefone E.164 e meta camelCase
- [x] Rejeita canal incompatível, contato sem telefone, telefone inválido, arquivo, texto e nota privada
- [x] `ChannelCapabilities::ShareContact`
- [x] Permissão `administrator`, `agent` ou `contact_manage` quando há usuário
- [x] `companyName` no meta

O gancho está em `Custom::Messages::MessageBuilder#process_attachments`, que chama `Custom::Messages::SharedContactHandler` antes de `super`.

---

## Fase 2 — WhatsApp Cloud e 360dialog

- [x] `Whatsapp::ContactMessagePayloadBuilder`
- [x] `Whatsapp::ContactDelivery` nos dois providers
- [x] `org.company` quando há empresa
- [x] Cloud envia `context` de reply-to
- [x] Specs dos dois providers

O body do 360dialog não inclui `context`. Os envios de texto e mídia desse provider também não citam a mensagem respondida.

---

## Fase 3 — Telegram

- [x] Bucket `:contact` em `group_attachments_by_type`
- [x] `POST .../sendContact`
- [x] `business_connection_id`
- [x] `reply_to_message_id`
- [x] Mensagem só de contato, sem texto
- [x] Spec em `send_attachments_service_spec`

---

## Fase 4 — Frontend

- [x] `ShareContactDialog.vue` e `ShareContactForm.vue`
- [x] Botão `i-ph-address-book` em `ReplyBottomPanel`
- [x] `ReplyBox` envia `sharedContactId` e preserva reply-to
- [x] Botão oculto em nota privada, sem permissão, e em Cloud/360dialog fora de `can_reply`
- [x] Gateways sem a janela de 24h
- [x] Pending message com attachment `contact`
- [x] Outgoing sem Save Contact, meta snake_case e `CONTACT_OUTGOING`
- [x] Preview da lista em `useMessagePreview.js`
- [x] `en` + `pt_BR`
- [x] Analytics `CONVERSATION_EVENTS.SHARED_CONTACT` depois do envio bem-sucedido
- [x] Atalho com `type="button"`; sem telefone mostra `NO_PHONE_CURRENT` e o link de edição
- [x] Busca só com telefone; empty state `NO_PHONE` quando todos os resultados não têm

---

## Fase 5 — Gateways

- [x] Evolution `sendContact`
- [x] Evolution Go vCard
- [ ] Z-API — não há provider Z-API neste fork

---

## Fora do que foi entregue

- LINE, Facebook, Instagram, SMS e inbox API
- Vários contatos ou vários telefones na mesma mensagem
- Feature flag
- Normalizer de echo
- Atalho de teclado e aviso ao compartilhar o contato da própria conversa

---

## Testes manuais

1. Atalho com telefone.
2. Busca de outro contato.
3. Contato da conversa sem telefone: mensagem e link, sem envio.
4. Busca que só acha contatos sem telefone: empty state de telefone obrigatório.
5. Cloud, 360dialog, Evolution, Evolution Go e Telegram: cartão no app do cliente.
6. Lista: "Shared contact" / "Contato compartilhado".
7. Inbound continua abrindo o bubble e, no incoming, o Save Contact.
8. Outgoing sem Save Contact.
9. Cloud ou 360dialog fora de 24h: botão ausente.
10. Telegram Business com `business_connection_id`.
11. Agente sem `contact_manage` e sem papel de agente/administrador: botão ausente e API recusa.

---

## Critérios de aceite

- [x] Atalho e busca
- [x] Cloud, 360dialog, Telegram, Evolution e Evolution Go
- [x] Bubble outgoing sem Save Contact
- [x] Preview da lista com ícone `contact`
- [x] `can_reply` em Cloud e 360dialog
- [x] E.164 obrigatório
- [x] `en` + `pt_BR`, inclusive `CONTACT_OUTGOING`
- [x] Permissão, empresa e analytics
- [x] Specs do handler, Cloud, 360dialog, Telegram e Evolution

---

## Referências

| Peça | Arquivo |
|------|---------|
| Estado atual | [current-state.md](./current-state.md) |
| UI | [ui-design.md](./ui-design.md) |
| Backlog | [improvements-backlog.md](./improvements-backlog.md) |
| Inbound WhatsApp | `app/services/whatsapp/incoming_message_base_service.rb` |
| Inbound Telegram | `app/services/telegram/incoming_message_service.rb` |
| Bubble | `components-next/message/bubbles/Contact.vue` |
| Reply bar | `components/widgets/WootWriter/ReplyBottomPanel.vue` |
