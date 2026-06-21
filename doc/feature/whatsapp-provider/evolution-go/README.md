# Evolution Go — Provider WhatsApp no Chatwoot

Planejamento para o segundo provider gateway do fork: **`Channel::Whatsapp`** com `provider: 'evolution_go'`, consumindo a [Evolution Go](https://docs.evolutionfoundation.com.br/en/evolution-go) via REST + webhooks.

**Relação com Evolution API (Node):** mesmo ecossistema Evolution Foundation, mas **contrato REST e eventos distintos** — não reutilizar `Custom::Whatsapp::Evolution::*` sem adaptação. Ver [differences-from-evolution-api.md](./differences-from-evolution-api.md).

| **Última atualização:** jun/2026 · fase **planejamento** (sem código) |

| Item | Estado |
|------|--------|
| **Documentação fork** | 25 arquivos — [índice](./evolution-go/README.md#índice-completo) |
| **Código Chatwoot (`custom/`)** | **Não iniciado** — nenhuma classe Evolution Go em `custom/` |
| **Versão alvo** | [evolution-target-version.txt](./evolution-target-version.txt) → **latest stable** (validar no spike) |
| **Evolution Go local** | **Não instalado** — spike recomendado via Docker antes da Fase 1 |
| **Postman** | [Evolution Go collection](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) — paths confirmados OpenAPI jun/2026 |

> **Antes da Fase 1:** executar [validation-checklist.md](./validation-checklist.md) contra servidor Evolution Go real. Congelar versão em [evolution-target-version.txt](./evolution-target-version.txt).

---

## Objetivo

| Hoje | Alvo (Chatwoot fork) |
|------|----------------------|
| Sem provider Evolution Go | Inbox **`Channel::Whatsapp`** `provider: 'evolution_go'` |
| Evolution API (`evolution`) **já em `custom/`** | Provider **independente** — adapter `EvolutionGo::*` separado |
| Regras Meta (24h, templates) não se aplicam | Bypass explícito de janela 24h — whatsmeow, texto livre |

**Regra crítica:** Evolution Go **não** possui integração nativa Chatwoot como a Evolution API Node (`/chatwoot/set`). O fork configura webhook + REST diretamente.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Entender diferenças vs Evolution API** | [differences-from-evolution-api.md](./differences-from-evolution-api.md) |
| **Implementar Fase 0–1** | [implementation-plan.md](./implementation-plan.md) → [validation-checklist.md](./validation-checklist.md) |
| **Regras adaptadas ao fork** | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| **Links oficiais (índice completo)** | [documentation-links.md](./documentation-links.md) (+ `sync-documentation-links.sh`) |
| **Postman — validação de endpoints** | [postman-validation.md](./postman-validation.md) |
| **Decisões fechadas** | [decisions.md](./decisions.md) |
| **Contratos das classes (`custom/`)** | [spec-design.md](./spec-design.md) |
| **Campos inbox ↔ APIs** | [provider-config-mapping.md](./provider-config-mapping.md) |
| **Endpoints REST** | [api-reference.md](./api-reference.md) |
| **Prontidão para código** | [implementation-readiness.md](./implementation-readiness.md) |
| **Gaps e melhorias** | [gaps-and-improvements.md](./gaps-and-improvements.md) |
| **Coordenação vs Evolution API** | [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) |
| **Tarefas (planejamento)** | [tasks.md](./tasks.md) |
| **Regras inbox + UI** | [inbox-business-rules.md](./inbox-business-rules.md) |
| **Wizard frontend** | [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| **Features por fase** | [feature-mapping.md](./feature-mapping.md) |
| **vs Cloud API Meta** | [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md) |
| **Troubleshooting** | [troubleshooting.md](./troubleshooting.md) |
| **Erros HTTP** | [error-handling.md](./error-handling.md) |

---

## Documentação externa (Evolution Go)

| Recurso | URL |
|---------|-----|
| Hub | https://docs.evolutionfoundation.com.br/en/evolution-go |
| Getting started | https://docs.evolutionfoundation.com.br/en/evolution-go/getting-started |
| Instalação | https://docs.evolutionfoundation.com.br/en/evolution-go/installation |
| GitHub | https://github.com/evolution-foundation/evolution-go |
| Docker Hub | https://hub.docker.com/r/evoapicloud/evolution-go |
| Postman | https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go |
| Swagger (runtime) | `{base_url}/swagger/index.html` |

Índice completo: [documentation-links.md](./documentation-links.md)

---

## Relação com documentação geral do fork

| Documento pai | Uso |
|---------------|-----|
| [../README.md](../README.md) | Visão geral providers alternativos |
| [../evolution-api/README.md](../evolution-api/README.md) | Provider irmão (Node/Baileys) — **não confundir** |
| [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md) | Infra Fase 0 (registry, prepends) |
| [../gaps-and-blockers.md](../gaps-and-blockers.md) | Bloqueios no código Chatwoot |
| [../feature-mapping.md](../feature-mapping.md) | Checklist feature a feature |
| [../STATUS.md](../STATUS.md) | Status consolidado fork |
| [../provider-comparison.md](../provider-comparison.md) | Evolution Go vs Evolution API vs Z-API |

---

## Provider key

```
provider: 'evolution_go'
```

Adicionar em `Channel::Whatsapp::PROVIDERS` com `# FORK:` (ver [../gaps-and-blockers.md](../gaps-and-blockers.md)). **Distinto** de `evolution` (Evolution API Node).

---

## Fase 1 — escopo

| Incluído | Fase 2+ |
|----------|---------|
| Conexão + instância + webhook no `connect` | Settings avançados (`advanced-settings`) |
| **Proxy opcional no wizard** | Mídia, status `READ_RECEIPT` |
| QR (`/instance/qr`) + pairing code (`/instance/pair`) | Import histórico (`HISTORY_SYNC`) |
| Texto in/out via `POST /send/text` | Botões/listas, reações |
| Eventos `MESSAGE`, `CONNECTION`, `QRCODE` | WebSocket / RabbitMQ (fora do fork) |
| Defaults fork ([business-rules-adaptation.md](./business-rules-adaptation.md)) | Chamadas (`CALL`) |

---

## Componentes previstos no fork (`custom/`)

| Classe | Fase | Responsabilidade |
|--------|------|------------------|
| `Custom::Whatsapp::EvolutionGo::ApiClient` | 1 | HTTP fino para Evolution Go |
| `Custom::Whatsapp::EvolutionGo::ConnectionService` | 1 | create/connect/webhook/proxy/QR/ActionCable |
| `Custom::Whatsapp::Providers::EvolutionGoService` | 1 | Envio texto, `process_response` |
| `Custom::Whatsapp::Webhooks::EvolutionGoNormalizer` | 1 | Envelope Go → flat payload |
| `Custom::Webhooks::EvolutionGoController` | 1 | Auth + enqueue job |
| Prepend `Channel::Whatsapp` | 0 | Registry → `EvolutionGoService` |
| Prepend `WhatsappEventsJob` | 0–1 | Normalizer antes de `IncomingMessageService` |
| Prepend `MessageWindowService` | 0 | `nil` para `evolution_go` |
| Vue wizard | 1 | Form mínimo + QR |

> **Não** estender `Custom::Whatsapp::Evolution::ApiClient` — paths, auth e eventos são diferentes.

---

## Decisão arquitetural: provider separado

| Opção | Prós | Contras | Decisão |
|-------|------|---------|---------|
| **A** — Reusar `provider: 'evolution'` com flag `engine: go` | Menos código UI | Normalizer e ApiClient divergem demais; confusão operacional | ❌ |
| **B** — Provider `evolution_go` dedicado | Contratos claros; evolução independente | Duplicação parcial de wizard/UI | **✅ MVP** |
| **C** — Abstração `GatewayEngine` compartilhada | DRY máximo | Over-engineering prematuro | Fase 3+ se padrão repetir |

---

## Brand assets (UI)

Reutilizar assets da Evolution Foundation (mesma marca):

| Asset | Destino no fork |
|-------|-----------------|
| `evolution-logo.png` | `custom/app/javascript/dashboard/assets/images/channels/evolution-go-logo.png` (ou reusar evolution-logo) |
| Card em `Whatsapp.vue` | **"Evolution Go"** — quarto sub-provider na tela WhatsApp |
| Cor marca | `#01b274` / `#00ffa7` (ver TRADEMARKS Evolution Foundation) |

**Fixtures:** `spec/fixtures/evolution_go/` — preencher via [validation-checklist.md](./validation-checklist.md).

---

## Índice completo

| # | Arquivo | Conteúdo |
|---|---------|----------|
| 1 | README.md | Este índice |
| 2 | [implementation-readiness.md](./implementation-readiness.md) | O que falta antes do código |
| 3 | [implementation-plan.md](./implementation-plan.md) | Fases 0–4 |
| 4 | [implementation-analysis.md](./implementation-analysis.md) | Stack e gaps |
| 5 | [decisions.md](./decisions.md) | ADRs §1–23 |
| 6 | [api-reference.md](./api-reference.md) | Endpoints REST |
| 7 | [documentation-links.md](./documentation-links.md) | Links oficiais + Postman |
| 8 | [postman-validation.md](./postman-validation.md) | Mapa collection |
| 9 | [webhook-events.md](./webhook-events.md) | Eventos + normalizer |
| 10 | [provider-config-mapping.md](./provider-config-mapping.md) | `provider_config` |
| 11 | [business-rules-adaptation.md](./business-rules-adaptation.md) | Defaults fork |
| 12 | [inbox-business-rules.md](./inbox-business-rules.md) | Regras inbox + settings |
| 13 | [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI wizard |
| 14 | [feature-mapping.md](./feature-mapping.md) | Features × fases |
| 15 | [spec-design.md](./spec-design.md) | Contratos `custom/` |
| 16 | [differences-from-evolution-api.md](./differences-from-evolution-api.md) | vs Node |
| 17 | [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md) | vs Meta |
| 18 | [validation-checklist.md](./validation-checklist.md) | Spike manual |
| 19 | [troubleshooting.md](./troubleshooting.md) | Operação |
| 20 | [error-handling.md](./error-handling.md) | Erros HTTP |
| 21 | [evolution-target-version.txt](./evolution-target-version.txt) | Versão alvo |
| 22 | [gaps-and-improvements.md](./gaps-and-improvements.md) | Auditoria doc |
| 23 | [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Coexistência Node |
| 24 | [tasks.md](./tasks.md) | Tarefas planejamento |
| 25 | [sync-documentation-links.sh](./sync-documentation-links.sh) | Diff `llms.txt` vs índice |

**Estado planejamento:** ~92% doc — falta spike runtime. Ver [implementation-readiness.md](./implementation-readiness.md), [gaps-and-improvements.md](./gaps-and-improvements.md), [../STATUS.md](../STATUS.md).
