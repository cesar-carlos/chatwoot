# Share Contact Card — Documentação

Plano para **envio de contact card pelo agente**, reutilizando inbound + UI existentes.

**Estado:** documentado · implementação pendente · **decisões fechadas (jun/2026)**

| Área | Status |
|------|--------|
| Inbound WhatsApp/Telegram | ✅ Existe |
| Exibição `Contact.vue` | ✅ Existe |
| Outbound (agente → cliente) | 📋 Planejado |
| UI ReplyBox | 📋 [ui-design.md](./ui-design.md) |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementar agora** | [implementation-plan.md](./implementation-plan.md) |
| **UI / componentes** | [ui-design.md](./ui-design.md) |
| **Por que esta abordagem** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **O que já existe** | [current-state.md](./current-state.md) |

---

## Decisões fechadas

| Tópico | Decisão |
|--------|---------|
| Modelo | Reusar `Attachment` `file_type: contact` |
| Canais MVP | WhatsApp Cloud + **360dialog** + Telegram |
| UI | `Dialog` + `ComboBox` + atalho contato da conversa |
| Ícones ReplyBox | `i-ph-address-book` (Phosphor) |
| i18n | **en + pt_BR** |
| Echo coexistence | Sem normalizer extra no MVP |

---

## Recomendação técnica (resumo)

1. API `shared_contact_id` → `MessageBuilder` cria attachment `contact`
2. Send: WhatsApp `type: contacts` (Cloud + 360dialog), Telegram `sendContact`
3. UI em `widgets/conversation/ShareContact/` seguindo `ContactMergeForm` + `ReplyBottomPanel`
4. Gateways Evolution → Fase 5 em `custom/`

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Inventário inbound, modelo, lacunas |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções, decisões de produto |
| [ui-design.md](./ui-design.md) | Componentes, estilos, i18n, wireframes |
| [implementation-plan.md](./implementation-plan.md) | Fases, arquivos, testes, fork |

---

*Última atualização: jun/2026*
