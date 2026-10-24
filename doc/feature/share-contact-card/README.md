# Share Contact Card — Documentação

Envio de contact card pelo agente, reutilizando o inbound e o bubble que já existiam.

**Estado:** implementado · atualizado out/2026

| Área | Status |
|------|--------|
| Inbound WhatsApp/Telegram | Existe |
| Exibição `Contact.vue` | Existe |
| Outbound Cloud, 360dialog, Telegram | Implementado |
| Outbound Evolution e Evolution Go | Implementado |
| UI ReplyBox | `ShareContact/` + `ReplyBottomPanel` |
| Permissão, E.164, empresa, analytics | Implementado |

O comportamento em produção está em [current-state.md](./current-state.md). Os outros arquivos guardam a decisão original e o que ainda falta.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Como funciona hoje** | [current-state.md](./current-state.md) |
| **UI / componentes** | [ui-design.md](./ui-design.md) |
| **Por que esta abordagem** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **O que foi entregue** | [implementation-plan.md](./implementation-plan.md) |
| **O que ainda falta** | [improvements-backlog.md](./improvements-backlog.md) |

---

## Decisões em vigor

| Tópico | Decisão |
|--------|---------|
| Modelo | `Attachment` `file_type: contact`, sem arquivo e sem `content` |
| API | `POST .../messages` com `shared_contact_id` |
| Canais | WhatsApp Cloud, 360dialog, Evolution, Evolution Go, Telegram |
| Telefone | E.164 obrigatório; número inválido rejeita a mensagem |
| Permissão | `administrator`, `agent` ou `contact_manage` |
| UI | `Dialog` + `ComboBox` + atalho do contato da conversa |
| Janela 24h | Botão oculto em Cloud e 360dialog quando `can_reply` é falso. Gateways e Telegram seguem sem essa janela |
| i18n | `en` + `pt_BR` |
| Echo coexistence | Sem normalizer extra |

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Inventário do que está no código |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções descartadas e decisões de produto |
| [ui-design.md](./ui-design.md) | Componentes, estados e i18n |
| [implementation-plan.md](./implementation-plan.md) | Fases entregues e arquivos |
| [improvements-backlog.md](./improvements-backlog.md) | Itens entregues e o que permanece aberto |

---

*Última atualização: out/2026*
