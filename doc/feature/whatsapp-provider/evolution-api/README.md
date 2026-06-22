# Evolution API — Provider WhatsApp no Chatwoot

Planejamento para o primeiro provider alternativo do fork: **`Channel::Whatsapp`** com `provider: 'evolution'`, consumindo a [Evolution API](https://docs.evolutionfoundation.com.br/evolution-api) via REST + webhooks — em vez da integração nativa Evolution→Chatwoot (inbox tipo `api` + SDK).

**Última atualização:** jun/2026

| Item | Estado |
|------|--------|
| **Documentação fork** | 20 arquivos nesta pasta (ver índice abaixo) |
| **Código Chatwoot (`custom/`)** | **Fase 0–4 implementada** (~95%) — ver [tasks.md](./tasks.md) |
| **Specs automatizados** | ✅ ~42 examples em `spec/custom/` + Playwright em `tests/playwright/` |
| **Validação T0 (REST spike)** | ✅ v2.3.6 local — fixtures reais, sendText `text` plano |
| **Versão produção** | **2.3.7** — [evolution-target-version.txt](./evolution-target-version.txt) |
| **E2E local** | ✅ §2–4 jun/2026 — wizard QR com scan real ainda manual |
| **Evolution API local (dev)** | `/root/evolution-api` v**2.3.6** @ `:8080` |
| **v2.4.0+** | Exige [licença](https://docs.evolutionfoundation.com.br/licensing) — ver [documentation-links.md § Compatibilidade](./documentation-links.md#compatibilidade-de-versão) |

> **Tarefas:** [tasks.md](./tasks.md) · Validação REST (T0) concluída — ver [validation-checklist.md §7](./validation-checklist.md#7-registro).

---

## Objetivo

| Hoje (Evolution) | Alvo (Chatwoot fork) |
|------------------|----------------------|
| Evolution configura Chatwoot (SDK + webhook `/chatwoot/webhook/`) | Chatwoot configura Evolution (REST + webhook Chatwoot) |
| Inbox tipo **API** no Chatwoot | Inbox **`Channel::Whatsapp`** `provider: 'evolution'` |
| Regras Meta (24h, templates) não se aplicam ao API channel | Bypass explícito de janela 24h — bot Baileys, texto livre |

**Regra crítica:** com provider nativo ativo, **desabilitar** a integração Chatwoot **dentro** da Evolution (`chatwoot.enabled: false`) para evitar mensagens duplicadas.

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementar Fase 0–1** | [implementation-plan.md](./implementation-plan.md) → [validation-checklist.md](./validation-checklist.md) |
| **Regras adaptadas ao fork** | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| **Regras = telas Evolution Manager** | [inbox-business-rules.md § Checklist UI](./inbox-business-rules.md#checklist--paridade-com-ui-evolution-manager) |
| **Links oficiais Evolution** | [documentation-links.md](./documentation-links.md) |
| **Postman v2.3 — validação de endpoints** | [postman-validation.md](./postman-validation.md) |
| **Tarefas paralelas (agentes)** | [tasks.md](./tasks.md) |
| **Migrar da integração legada** | [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) |
| **Problemas em produção** | [troubleshooting.md](./troubleshooting.md) |
| Contexto integração atual Evolution | [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md) |
| **Regras de negócio e UI** | [inbox-business-rules.md](./inbox-business-rules.md) |
| Análise código Evolution | [implementation-analysis.md](./implementation-analysis.md) |
| **Decisões fechadas** | [decisions.md](./decisions.md) |
| Contratos das classes (`custom/`) | [spec-design.md](./spec-design.md) |
| Campos inbox ↔ APIs | [provider-config-mapping.md](./provider-config-mapping.md) |
| Endpoints REST | [api-reference.md](./api-reference.md) |
| Webhooks e normalizer | [webhook-events.md](./webhook-events.md) |
| Diferenças vs Cloud API | [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md) |

---

## Documentação externa (Evolution)

Índice completo, OpenAPI, discrepâncias doc vs código e script de manutenção: **[documentation-links.md](./documentation-links.md)**

- Hub: https://docs.evolutionfoundation.com.br/evolution-api
- Índice máquina: https://docs.evolutionfoundation.com.br/llms.txt
- Repositório: [evolution-foundation/evolution-api](https://github.com/evolution-foundation/evolution-api)

Código analisado localmente: `/root/evolution-api` — ver tabelas em [implementation-analysis.md](./implementation-analysis.md).

---

## Relação com documentação geral do fork

| Documento pai | Uso |
|---------------|-----|
| [../README.md](../README.md) | Visão geral providers alternativos |
| [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md) | Infra Fase 0 (registry, prepends) |
| [../gaps-and-blockers.md](../gaps-and-blockers.md) | Bloqueios no código Chatwoot |
| [../feature-mapping.md](../feature-mapping.md) | Checklist feature a feature |
| [../provider-comparison.md](../provider-comparison.md) | Evolution vs Z-API vs NotificaMe |
| [../evolution-go/coordination-with-evolution-api.md](../evolution-go/coordination-with-evolution-api.md) | Coexistência com Evolution Go (doc) |
| [../STATUS.md](../STATUS.md) | Status consolidado fork |

---

## Provider key

```
provider: 'evolution'
```

Registrado em `Channel::Whatsapp::PROVIDERS` com `# FORK:` (ver [../gaps-and-blockers.md](../gaps-and-blockers.md)).

---

## Escopo por fase

| Fase | Estado | Incluído |
|------|--------|----------|
| **0–1** | ✅ código | Registry, texto in/out, QR wizard, proxy wizard, webhook, bypass 24h, create pós-inbox + compensação |
| **2** | ✅ código | Mídia in/out (base64), statuses, settings UI, `sign_msg`, `ignore_jids`, `conversation_pending` |
| **3** | ✅ código | Health, reconnect/logout/restart, alerta desconexão, `merge_brazil_contacts`, ActionCable QR |
| **4** | ✅ código (validação operacional pendente) | Import histórico (`findContacts` / `findMessages`) via `ImportService` |
| **5** | — | Voz — ver `doc/feature/whatsapp-voice/` |

**Pendente validação operacional:** E2E §2–4 em [validation-checklist.md](./validation-checklist.md).

Detalhe: [inbox-business-rules.md](./inbox-business-rules.md) · [tasks.md](./tasks.md).

---

## Componentes no fork (`custom/`)

| Classe / arquivo | Fase | Responsabilidade |
|------------------|------|------------------|
| `Custom::Whatsapp::Evolution::ApiClient` | 1 | HTTP fino para Evolution (`ApiClient.for_channel`) |
| `Custom::Whatsapp::Evolution::ConnectionService` | 1–3 | Facade: connect/webhook/QR/ActionCable + delete compensação |
| `Custom::Whatsapp::Evolution::Provisioner` | 1–3 | create/connect/webhook/settings/proxy provision |
| `Custom::Whatsapp::Evolution::ConnectionEvents` | 1–3 | `CONNECTION_UPDATE` / `QRCODE_UPDATED` handlers |
| `Custom::Whatsapp::Evolution::MediaPayload` | 2 | base64 outbound quando URL não é pública |
| `Custom::Whatsapp::Evolution::ProviderConfig` | 0–2 | DEFAULTS, RUNTIME/SYNCABLE/CREDENTIAL keys |
| `Custom::Whatsapp::Providers::EvolutionService` | 1–2 | Envio texto/mídia, quoted, sign_msg |
| `Custom::Whatsapp::Webhooks::EvolutionNormalizer` | 1–2 | Envelope → flat payload |
| `Webhooks::EvolutionController` | 1 | Auth + enqueue job (`EventNames` no payload) |
| `Custom::Whatsapp::Evolution::EventNames` | 1 | `messages.upsert` → `MESSAGES_UPSERT` |
| Prepend `Channel::Whatsapp` | 0–2 | Registry, mask secrets, sync/validate condicional |
| Prepend `WhatsappEventsJob` | 0–1 | Normalizer + mutex Redis |
| Prepend `MessageWindowService` | 0 | `nil` para `evolution` |
| Prepend `Message` | 2 | delete sync, `conversation_pending`, import guards |
| `Custom::Whatsapp::Evolution::Broadcaster` | 3 | ActionCable desconexão |
| `Custom::Whatsapp::Evolution::ImportService` + import/* | 4 | Import histórico batelado |
| `Custom::Whatsapp::Evolution::ContactsSyncService` | 2 | Webhooks `CONTACTS_*` → contatos + enrichment |
| `Custom::Whatsapp::Evolution::DeleteSyncService` | 2 | Delete outbound → `deleteMessageForEveryone` |
| `Custom::Whatsapp::Evolution::ContactEnrichmentService` | 2 | Foto/perfil via APIs `/chat/fetch*` |
| `EvolutionSettingsPage.vue` + `EvolutionHealthPage.vue` | 2–3 | Settings + health/reconnect |
| `Evolution.vue` | 1 | Wizard form + etapa conectar |
| `EvolutionQrScanModal.vue` + `useEvolutionQrSession.js` | 1–3 | Modal QR (wizard + health), polling/expiry |
| `useEvolutionConnectionCable.js` | 1–3 | ActionCable `EvolutionConnectionChannel` |

---

## Brand assets e UX (UI)

Logo oficial da Evolution API para tiles e wizard:

| Asset | Origem | Destino no fork |
|-------|--------|-------------------|
| `evolution-logo.png` (504×505, verde) | `evolution-api/public/images/evolution-logo.png` | `custom/app/javascript/dashboard/assets/images/channels/evolution-logo.png` |
| Ícone 24px | `theme/icons.js` → `i-woot-evolution-color` | Tile `ChannelList` + card em `Whatsapp.vue` |
| Verde marca | `#01b274` (light) / `#00ffa7` (neon, dark) | `TRADEMARKS.md` no repo [evolution-foundation/evolution-api](https://github.com/evolution-foundation/evolution-api/blob/main/TRADEMARKS.md) |

**Como criar inbox Evolution (dois caminhos):**

1. **Configurações → Caixas de Entrada → Adicionar → Evolution API** — tile dedicado no grid (`ChannelList.vue` + `ChannelFactory.vue`)
2. **WhatsApp → Evolution API** — sub-provider em `Whatsapp.vue` (mesmo wizard `Evolution.vue`)

**Uso no wizard:** logo na etapa "Caixa de entrada criada"; QR no modal `EvolutionQrScanModal` (não inline na página).

**Fixtures:** `spec/fixtures/evolution/` — T0 REST concluído; E2E Playwright em `tests/playwright/tests/e2e/{api,ui}/evolution-inbox-create.spec.ts` (requer credenciais reais em `.env`).

---

## Hardening recente (jun/2026)

| Fix | Descrição |
|-----|-----------|
| P0 | Updates runtime (`connection_status`, QR) via `update_columns` — sem sync/validate remoto em webhooks |
| P2 | `MediaPayload` — mídia outbound em base64 quando URL não é pública |
| P3 | Create: inbox salvo antes do provision; falha remove inbox/channel + `DELETE /instance/delete` |
| Create | `rescue StandardError` com cleanup — evita inbox órfão em timeout/rede |
| Ruby 3.4 | `MessagingProvider::Capabilities` — `self.for(provider)` ( `for` é palavra reservada) |
| UX jun/2026 | Modal QR (`EvolutionQrScanModal`); help text `AUTHENTICATION_API_KEY`; anti-duplicata create |
| Seg jun/2026 | `apikey` removido do job Sidekiq; `ApiError#user_message` sanitizado em produção; `filter_parameter_logging` `:apikey` |
| Auth jun/2026 | `webhook_token` gerado no provision; URL webhook com `?token=`; auth secundária no controller |
| Ops jun/2026 | `ensure_chatwoot_integration_disabled!` verifica `GET /chatwoot/find` — falha provision se legado ativo |
| Outbound jun/2026 | Anexos parciais: 1º enviado mantém `source_id`; falhas 2º+ geram nota privada (não marca `failed`) |
| Ops jun/2026 | Trim credenciais (`ProviderConfig.normalize_credentials`); validação `instance_name` único antes do create |
| QR jun/2026 | `fetch_qr_code` reutiliza `qrcode_storage_attrs` — preserva `code` do connect flat; cable `QRCODE_UPDATED` emite `qrcode_base64`/`qrcode_code` (paridade API) |
| Inbound jun/2026 | `EventNames` normaliza `messages.upsert` → `MESSAGES_UPSERT`; job loga `[EVOLUTION] normalizer skipped` quando filtro retorna `nil` |
| LID jun/2026 | `resolve_wa_id` usa `remoteJidAlt` para `@lid` mesmo sem `addressingMode` |
| Refactor jun/2026 | `Provisioner` (create/webhook/settings) + `ConnectionEvents` (CONNECTION/QRCODE); `ConnectionService` facade; `ApiClient.for_channel` |
| Validação jun/2026 | `validate_provider_config?` exige `connectionState` → `open`; runtime keys não disparam sync/validate remoto |

---

## Índice (20 arquivos + scripts)

| # | Arquivo |
|---|---------|
| 1 | README.md |
| 2 | [implementation-plan.md](./implementation-plan.md) |
| 3 | [implementation-analysis.md](./implementation-analysis.md) |
| 4 | [decisions.md](./decisions.md) |
| 5 | [api-reference.md](./api-reference.md) |
| 6 | [documentation-links.md](./documentation-links.md) |
| 7 | [postman-validation.md](./postman-validation.md) |
| 8 | [webhook-events.md](./webhook-events.md) |
| 9 | [provider-config-mapping.md](./provider-config-mapping.md) |
| 10 | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| 11 | [inbox-business-rules.md](./inbox-business-rules.md) |
| 12 | [spec-design.md](./spec-design.md) |
| 13 | [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md) |
| 14 | [validation-checklist.md](./validation-checklist.md) |
| 15 | [troubleshooting.md](./troubleshooting.md) |
| 16 | [tasks.md](./tasks.md) |
| 17 | [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) |
| 18 | [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md) |

Scripts: [sync-documentation-links.sh](./sync-documentation-links.sh) · Versão: [evolution-target-version.txt](./evolution-target-version.txt)
