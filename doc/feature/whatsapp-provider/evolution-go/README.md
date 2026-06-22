# Evolution Go — Integração WhatsApp no Chatwoot

Planejamento do provider **`Channel::Whatsapp`** com `provider: 'evolution_go'`, consumindo [Evolution Go](https://docs.evolutionfoundation.com.br/en/evolution-go) via REST + webhooks.

| **Última atualização:** 22/jun/2026 · fase **integração** (sem código) |

---

## Escopo

| Incluído no fork | Fora do escopo |
|------------------|----------------|
| Adapter REST (`ApiClient`, `ConnectionService`) | Provisionar / subir Evolution Go |
| Webhook receiver + normalizer | Licenciamento Magic Link no painel Go |
| Wizard de inbox + QR via backend | PostgreSQL, Docker, proxy do servidor Go |
| Registry, prepends, specs | Manutenção do repositório `evolution-foundation/evolution-go` |

**Regra crítica:** Evolution Go **não** tem integração nativa Chatwoot (`/chatwoot/set` como na Evolution API Node). O fork configura `webhookUrl` + REST diretamente no `POST /instance/connect`.

**Relação com Evolution API (Node):** mesmo ecossistema Evolution Foundation, mas **contrato REST e eventos distintos** — namespace `Custom::Whatsapp::EvolutionGo::*` separado. Ver [differences-from-evolution-api.md](./differences-from-evolution-api.md).

---

## Estado atual

| Item | Estado |
|------|--------|
| Documentação | ✅ consolidada — [status.md](./status.md) |
| Código `custom/` | ❌ não iniciado |
| Contrato API | ✅ Postman + OpenAPI — [postman-validation.md](./postman-validation.md) |
| Instância Evolution Go | **Externa** — operador fornece `base_url` + chaves |

---

## Objetivo

| Hoje | Alvo |
|------|------|
| Sem provider Evolution Go | Inbox `provider: 'evolution_go'` |
| Evolution API (`evolution`) em `custom/` | Provider **independente** — `EvolutionGo::*` |
| Regras Meta (24h, templates) | Bypass janela 24h — whatsmeow, texto livre |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Status e lacunas** | [status.md](./status.md) |
| **Implementar** | [implementation-plan.md](./implementation-plan.md) → [tasks.md](./tasks.md) |
| **Diferenças vs Evolution API** | [differences-from-evolution-api.md](./differences-from-evolution-api.md) |
| **Decisões (ADRs)** | [decisions.md](./decisions.md) |
| **Contratos `custom/`** | [spec-design.md](./spec-design.md) |
| **Endpoints REST** | [api-reference.md](./api-reference.md) |
| **Webhooks** | [webhook-events.md](./webhook-events.md) |
| **Config inbox** | [provider-config-mapping.md](./provider-config-mapping.md) |
| **Regras de negócio** | [business-rules-adaptation.md](./business-rules-adaptation.md), [inbox-business-rules.md](./inbox-business-rules.md) |
| **Wizard UI** | [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| **E2E com instância operador** | [validation-checklist.md](./validation-checklist.md) |
| **Coexistência Node** | [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) |
| **Links oficiais** | [documentation-links.md](./documentation-links.md) |
| **Erros / troubleshooting** | [error-handling.md](./error-handling.md), [troubleshooting.md](./troubleshooting.md) |

---

## Stack Evolution Go (referência)

| Componente | Tecnologia |
|------------|------------|
| WhatsApp | whatsmeow (fork Evolution Foundation) |
| Auth REST | `GLOBAL_API_KEY` (admin) + `instance_token` (operações) |
| Webhook | Configurado inline no `connect` — eventos `MESSAGE`, `CONNECTION`, `QRCODE` |
| Docs API | OpenAPI + Postman + Swagger `{base_url}/swagger/index.html` |

Detalhe técnico: [api-reference.md](./api-reference.md) · análise de payloads: [webhook-events.md](./webhook-events.md)

---

## Provider key

```
provider: 'evolution_go'
```

Adicionar em `Channel::Whatsapp::PROVIDERS` com `# FORK:`. **Distinto** de `evolution` (Evolution API Node).

---

## Fases de implementação

| Fase | Escopo |
|------|--------|
| **0** | Registry, prepends, rota webhook stub |
| **1** | Texto in/out, connect, QR, wizard |
| **2** | Mídia, `READ_RECEIPT`, `advanced-settings` |
| **3** | Interativos, health, reconnect |
| **4** | `HISTORY_SYNC` |

Matriz completa: [feature-mapping.md](./feature-mapping.md) · plano: [implementation-plan.md](./implementation-plan.md)

---

## Componentes previstos (`custom/`)

| Classe | Fase |
|--------|------|
| `Custom::Whatsapp::EvolutionGo::ApiClient` | 1 |
| `Custom::Whatsapp::EvolutionGo::ConnectionService` | 1 |
| `Custom::Whatsapp::Providers::EvolutionGoService` | 1 |
| `Custom::Whatsapp::Webhooks::EvolutionGoNormalizer` | 1 |
| `Custom::Webhooks::EvolutionGoController` | 1 |
| Prepend `Channel::Whatsapp`, `WhatsappEventsJob`, `MessageWindowService` | 0 |
| Wizard Vue | 1 |

> **Não** estender `Custom::Whatsapp::Evolution::ApiClient` — paths, auth e eventos são diferentes.

---

## Decisão: provider separado

Provider dedicado `evolution_go` (não flag `engine: go` em `evolution`). Ver [decisions.md](./decisions.md) e [coordination-with-evolution-api.md](./coordination-with-evolution-api.md).

---

## Documentação externa

| Recurso | URL |
|---------|-----|
| Hub | https://docs.evolutionfoundation.com.br/en/evolution-go |
| Postman | https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go |
| GitHub | https://github.com/evolution-foundation/evolution-go |

Índice completo: [documentation-links.md](./documentation-links.md) · sync: `./sync-documentation-links.sh`

---

## Documentação pai

| Documento | Uso |
|-----------|-----|
| [../README.md](../README.md) | Visão geral providers |
| [../evolution-api/README.md](../evolution-api/README.md) | Provider irmão (Node) |
| [../STATUS.md](../STATUS.md) | Status consolidado fork |
| [../provider-comparison.md](../provider-comparison.md) | Node vs Go vs Z-API |

---

## Índice de arquivos

| Arquivo | Conteúdo |
|---------|----------|
| README.md | Este índice |
| [status.md](./status.md) | Status, lacunas, prontidão |
| [tasks.md](./tasks.md) | Tarefas de implementação |
| [implementation-plan.md](./implementation-plan.md) | Fases 0–4 |
| [decisions.md](./decisions.md) | ADRs §1–26 |
| [spec-design.md](./spec-design.md) | Contratos Ruby |
| [api-reference.md](./api-reference.md) | Endpoints REST |
| [webhook-events.md](./webhook-events.md) | Eventos + normalizer |
| [provider-config-mapping.md](./provider-config-mapping.md) | `provider_config` |
| [business-rules-adaptation.md](./business-rules-adaptation.md) | Defaults fork |
| [inbox-business-rules.md](./inbox-business-rules.md) | Regras inbox |
| [frontend-wizard-spec.md](./frontend-wizard-spec.md) | UI wizard |
| [feature-mapping.md](./feature-mapping.md) | Features × fases |
| [differences-from-evolution-api.md](./differences-from-evolution-api.md) | vs Node |
| [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md) | vs Meta |
| [validation-checklist.md](./validation-checklist.md) | E2E instância operador |
| [postman-validation.md](./postman-validation.md) | Audit Postman |
| [documentation-links.md](./documentation-links.md) | Links oficiais |
| [coordination-with-evolution-api.md](./coordination-with-evolution-api.md) | Coexistência Node |
| [troubleshooting.md](./troubleshooting.md) | Operação |
| [error-handling.md](./error-handling.md) | Erros HTTP |
| [evolution-target-version.txt](./evolution-target-version.txt) | Versão servidor operador |
| [sync-documentation-links.sh](./sync-documentation-links.sh) | Diff `llms.txt` |
