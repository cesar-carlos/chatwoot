# Documentação oficial Wavoip — referência para implementação

Índice curado da documentação **[Wavoip GitBook](https://wavoip.gitbook.io/api)** para consulta durante o desenvolvimento no Chatwoot. Em caso de dúvida, **consulte aqui antes** de inferir comportamento.

**Doc interna relacionada:** [contracts-and-ports.md](./contracts-and-ports.md) (portas, DI, DTOs) · [sdk-reference.md](./sdk-reference.md) (mapeamento Chatwoot) · [webhook-contract.md](./webhook-contract.md) (HTTP/ActionCable)

---

## Índices e busca dinâmica

| Recurso | URL | Quando usar |
|---------|-----|-------------|
| **Índice completo (llms.txt)** | https://wavoip.gitbook.io/api/llms.txt | Descobrir páginas disponíveis |
| **Sitemap** | https://wavoip.gitbook.io/api/sitemap.md | Navegar estrutura do GitBook |
| **Export completo** | https://wavoip.gitbook.io/api/llms-full.txt | Busca offline / corpus inteiro |
| **Portal** | https://wavoip.gitbook.io/api | Leitura humana no browser |

### Consulta por pergunta (`?ask=`)

Qualquer página `.md` aceita pergunta em linguagem natural:

```
GET https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md?ask=O que acontece quando acceptedElsewhere é emitido?
```

Útil quando a resposta não está na doc interna do fork ou a API mudou.

### Convenção de URLs

- Anexar **`.md`** à URL da página para markdown estruturado (ex.: `.../device.md`)
- Pacote npm: [@wavoip/wavoip-api](https://www.npmjs.com/package/@wavoip/wavoip-api)
- Painel admin: [app.wavoip.com/devices](https://app.wavoip.com/devices)

---

## Por fase de implementação (Chatwoot)

| Fase | Dúvida típica | Doc oficial |
|------|---------------|-------------|
| **0 — Spike** | Como instalar e inicializar o SDK? | [Instalação](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/installation.md) · [Inicialização](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/initialization.md) |
| **0 — Spike** | Formato dos eventos HTTP? | [Webhook (Beta)](https://wavoip.gitbook.io/api/webhook-beta.md) |
| **1 — Canal** | Como obter token / vincular WhatsApp? | [Vincule um Whatsapp](https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp.md) · [app.wavoip.com/devices](https://app.wavoip.com/devices) |
| **1 — Canal** | Configurar webhook no painel Wavoip | [Webhook (Beta) — configuração](https://wavoip.gitbook.io/api/webhook-beta.md) |
| **1 — Device panel** | Status, QR, `wakeUp`, `pairingCode` | [Dispositivo](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md) |
| **2 — Outbound** | `startCall`, erros por device | [Chamadas realizadas](https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md) · [Inicialização — startCall](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/initialization.md) |
| **2 — Outbound** | Gesto do usuário / AudioContext | [Mídia](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md) |
| **3 — Inbound** | `offer`, `accept`, `reject`, multi-aba | [Chamadas recebidas](https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md) |
| **3 — Inbound** | Eventos `CALL` inbound no servidor | [Webhook — evento CALL](https://wavoip.gitbook.io/api/webhook-beta.md) |
| **4 — Gravação** | URL e disponibilidade da gravação | [Gravação](https://wavoip.gitbook.io/api/gravacao.md) · webhook `RECORD` |
| **5 — Diagnóstico** | ICE, STUN, `connectivityIssue` | [Solução de problemas](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md) · [Tipos — ICE](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md) |
| **Qualquer** | Tipos TypeScript exportados | [Tipos](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md) |

---

## `@wavoip/wavoip-api` (SDK — usar no Chatwoot)

Biblioteca **browser-only** — base da integração Vue.

| Tópico | URL |
|--------|-----|
| Introdução | https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/readme.md |
| Instalação | https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/installation.md |
| Inicialização (`Wavoip`, `on('offer')`, `startCall`) | https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/initialization.md |
| **Dispositivo** — status, QR, `wakeUp`, `pairingCode` | https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md |
| **Mídia** — mic/speaker, AudioContext | https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/media.md |
| **Chamadas recebidas** — `Offer`, `accept`, `reject` | https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md |
| **Chamadas realizadas** — `startCall`, `CallOutgoing` | https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md |
| **Chamada ativa** — mute, end, stats, reconnect | https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md |
| **Tipos** — `CallStatus`, `DeviceStatus`, ICE, etc. | https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md |
| **Solução de problemas** — `connectivityIssue` | https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md |

---

## Plataforma Wavoip (painel, webhook, gravação)

| Tópico | URL |
|--------|-----|
| Bem-vindo / visão geral | https://wavoip.gitbook.io/api/comece-aqui/quickstart.md |
| Manual de boas práticas (2025) | https://wavoip.gitbook.io/api/comece-aqui/manual-de-boas-praticas-wavoip-2025.md |
| **Webhook (Beta)** — `CALL`, `RECORD`, `DEVICE` | https://wavoip.gitbook.io/api/webhook-beta.md |
| **Gravação** | https://wavoip.gitbook.io/api/gravacao.md |
| Vincule um WhatsApp | https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp.md |
| Configurações gerais do dispositivo | https://wavoip.gitbook.io/api/dispositivo/configuracoes-gerais.md |
| WhatsApp externo / Evolution / Baileys | https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp/whatsapp-externo.md · [Evolution](https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp/whatsapp-externo/evolution.md) · [Baileys](https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp/whatsapp-externo/baileys.md) |

> **Nota fork:** auth do webhook usa `webhook_key` opaca na URL — ver
> [webhook-contract.md](./webhook-contract.md). A doc Wavoip não descreve assinatura HMAC.

---

## Webphone (`@wavoip/wavoip-webphone`) — só referência de comportamento

**Não instalar** no Chatwoot. Consultar apenas para replicar UX (notificações, diagnóstico):

| Tópico | URL |
|--------|-----|
| Introdução | https://wavoip.gitbook.io/api/webphone/readme.md |
| Inicialização | https://wavoip.gitbook.io/api/webphone/primeiros-passos/inicializacao.md |
| API pública `window.wavoip` | https://wavoip.gitbook.io/api/webphone/referencia/api-publica.md |
| Notificações push | https://wavoip.gitbook.io/api/webphone/recursos/notificacoes-push.md |
| Diagnóstico de chamada | https://wavoip.gitbook.io/api/webphone/recursos/diagnostico.md |
| Cores e tema | https://wavoip.gitbook.io/api/webphone/customizacao/cores.md |

---

## Mapa rápido: dúvida → onde olhar

| Se você está implementando… | Doc oficial |
|----------------------------|-------------|
| `PayloadNormalizer` / handlers Rails | [Webhook (Beta)](https://wavoip.gitbook.io/api/webhook-beta.md) + [fixtures/](./fixtures/) |
| `useWavoipConnection` | [Inicialização](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/initialization.md) · [Dispositivo](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md) |
| `useWavoipIncomingOffer` | [Incoming](https://wavoip.gitbook.io/api/wavoip-api/chamadas/incoming.md) |
| `useWavoipOutboundCall` | [Outgoing](https://wavoip.gitbook.io/api/wavoip-api/chamadas/outgoing.md) |
| `useWavoipActiveCall` | [Active](https://wavoip.gitbook.io/api/wavoip-api/chamadas/active.md) |
| `StatusMapper` (webhook) | [Webhook CALL.status](https://wavoip.gitbook.io/api/webhook-beta.md) |
| `callStatusUI.js` (SDK) | [Tipos — CallStatus](https://wavoip.gitbook.io/api/wavoip-api/referencia/types.md) |
| `RecordHandler` | [Webhook RECORD](https://wavoip.gitbook.io/api/webhook-beta.md) · [Gravação](https://wavoip.gitbook.io/api/gravacao.md) |
| `DeviceHandler` | [Webhook DEVICE](https://wavoip.gitbook.io/api/webhook-beta.md) · [Dispositivo](https://wavoip.gitbook.io/api/wavoip-api/conceitos-fundamentais/device.md) |
| Toast `connectivityIssue` | [Troubleshooting](https://wavoip.gitbook.io/api/wavoip-api/referencia/troubleshooting.md) |
| Wizard / pareamento | [Vincule um Whatsapp](https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp.md) · [operations-runbook.md](./operations-runbook.md) |

---

## Manutenção deste índice

Ao encontrar URL quebrada ou página renomeada no GitBook Wavoip:

1. Consultar https://wavoip.gitbook.io/api/llms.txt ou https://wavoip.gitbook.io/api/sitemap.md
2. Atualizar este arquivo e [sdk-reference.md](./sdk-reference.md)
3. Validar com `GET <url>.md?ask=...` se o conteúdo mudou
