# Contratos, portas e inversão de dependência — Wavoip

**Fonte única** para limites entre Chatwoot (domínio/orquestração) e Wavoip (infraestrutura). Objetivo: implementar o primeiro provider alternativo **sem god class**, **sem acoplar** o core ao SDK ou ao formato webhook Wavoip.

**Relacionado:** [architecture.md](./architecture.md) · [webhook-contract.md](./webhook-contract.md) · [frontend-integration.md](./frontend-integration.md) · [sdk-reference.md](./sdk-reference.md) · [../architecture-and-flow.md §13](../architecture-and-flow.md#13-roadmap-de-refatoração-melhorias-sugeridas)

**Última revisão:** jun/2026.

---

## 1. Princípios (rules do projeto)

| Rule (`architecture.mdc`) | Aplicação Wavoip |
|---------------------------|------------------|
| Domain — invariantes, sem HTTP | `Call`, status terminal, unique `(provider, provider_call_id)` |
| Application — uma ação por classe | Handlers por `type`/`action`; sem `WavoipService` monolítico |
| Transport — delegar | `WavoipController` → job → dispatcher → handler |
| Infrastructure — APIs externas | `@wavoip/wavoip-api` **só** em composables `custom/`; webhook parse em `PayloadNormalizer` |
| Fork merge-safe | Portas estáveis em `custom/`; upstream recebe hooks pequenos e inventariados |

**Regra de ouro (repetida porque é contrato):**

| Camada | Dono de quê |
|--------|-------------|
| **Browser + SDK** | `accept` / `reject` / `startCall` / `end` / mute / WebRTC |
| **Servidor Rails** | Contato, conversa, `Call`, bolha `voice_call`, ActionCable auxiliar, gravação via URL |
| **Webhook Wavoip** | Histórico e transições de status **autoritativas** para CRM |
| **SDK `offer`** | Ring em tempo real + áudio; pode chegar **antes** do webhook |

Nunca inverter: o servidor **não** aceita chamada Wavoip; o browser **não** cria `Conversation` sozinho.

---

## 2. Visão hexagonal

```mermaid
flowchart TB
  subgraph Core["Núcleo Chatwoot (não conhece Wavoip)"]
    ICB[Voice::InboundCallBuilder]
    CMB[Voice::CallMessageBuilder]
    CALL[Call model]
    UCS[useCallSession]
    STORE[calls.js Pinia]
    FCW[FloatingCallWidget]
  end

  subgraph Ports["Portas — contratos estáveis"]
    P_WH[Voice::Port::WebhookIngress]
    P_BC[Voice::Port::CallBroadcaster]
    P_SL[Voice::Port::StatusMapper]
    P_BS[BrowserVoice::Port::Session]
    P_BCable[BrowserVoice::Port::CableHandlers]
  end

  subgraph AdaptersWavoip["Adaptadores Wavoip (custom/)"]
    AW_WH[Wavoip::PayloadNormalizer + Handlers]
    AW_BC[Wavoip::Calls::Broadcaster]
    AW_SL[Wavoip::Calls::StatusMapper]
    AW_BS[useWavoipCallSession + composables]
    AW_Cable[wavoipVoiceCableHandlers]
  end

  subgraph AdaptersMeta["Adaptadores Meta (existentes)"]
    AM_WH[Whatsapp::IncomingCallService]
    AM_BS[useWhatsappCallSession]
    AM_Cable[whatsappVoiceCableHandlers]
  end

  subgraph External["Externo"]
    WAV_HTTP[Webhook HTTP Wavoip]
    WAV_SDK["@wavoip/wavoip-api"]
  end

  WAV_HTTP --> AW_WH
  AW_WH --> P_WH
  P_WH --> ICB & CMB & CALL
  AW_BC --> P_BC
  P_BC --> STORE
  AW_SL --> P_SL
  P_SL --> CALL

  WAV_SDK --> AW_BS
  AW_BS --> P_BS
  P_BS --> UCS
  UCS --> STORE & FCW
  AW_Cable --> P_BCable
  P_BCable --> STORE

  AM_WH --> ICB
  AM_BS --> P_BS
  AM_Cable --> P_BCable
```

**Direção das dependências:** adaptadores → portas → núcleo. O núcleo **nunca** importa `Wavoip`, `PayloadNormalizer` nem `@wavoip/wavoip-api`.

---

## 3. Fontes da verdade (evitar duplicidade conflitante)

| Dado | Fonte primária | Fonte secundária | Regra de reconciliação |
|------|----------------|------------------|------------------------|
| `Call.status` (CRM) | Webhook `CALL UPDATE` | SDK events | Servidor ganha; SDK só UI live |
| Ring inbound (widget) | SDK `on('offer')` | ActionCable `voice_call.incoming` | Unir por `provider_call_id` / `offer.id` |
| `accepted_by_agent_id` | `PATCH` após `offer.accept()` (MVP+) | Webhook `ACTIVE` | Preferir PATCH; webhook pode deixar `nil` |
| Contato / conversa | `ConversationLinker` + EE builder | — | Só servidor |
| Bolha `voice_call` | `CallMessageBuilder` | — | Criada no `CREATE` webhook ou idempotente |
| Gravação | Webhook `RECORD` → `record_url` | — | Sem `MediaRecorder` no browser |
| Dispositivo pronto | SDK `Device.status === 'open'` | Webhook `DEVICE` (cache) | SDK para UX agente; webhook para admin offline |
| Duração | Webhook `ENDED` + `duration` | Timer UI | Persistir duração do webhook |

---

## 4. Contratos backend (Ruby)

### 4.1 DTO normalizado (saída do parser — entrada dos handlers)

Objeto **imutável** após `PayloadNormalizer`. Handlers só recebem este shape, nunca `params` cru.

```ruby
# custom/app/services/voice/dto/webhook_call_event.rb
Voice::Dto::WebhookCallEvent = Data.define(
  :provider,           # :wavoip
  :external_call_id,    # whatsapp_call_id (string)
  :action,             # :create | :update
  :external_status,    # "INCOMING_RING", "ACTIVE", … (vocabulário Wavoip)
  :direction,          # :incoming | :outgoing | nil
  :from_phone,         # E.164 ou nil
  :to_phone,           # E.164 ou nil
  :peer_name,          # string | nil
  :duration_seconds,   # integer | nil
  :session_id,         # id_session webhook | nil
  :call_type,          # :official | :unofficial | nil
  :record_url,         # só em RECORD
  :raw_type            # "CALL" | "RECORD" | "DEVICE" — debug only
) do
  def create? = action == :create
  def update? = action == :update
end
```

**Responsabilidade única:** `Wavoip::Webhooks::PayloadNormalizer` traduz JSON Wavoip → `WebhookCallEvent`. Bug do campo `type` duplicado no payload fica **contido** aqui.

### 4.2 Porta `Voice::Port::StatusMapper`

```ruby
# custom/app/services/voice/port/status_mapper.rb
module Voice::Port::StatusMapper
  # @param external_status [String] vocabulário do provider
  # @return [String, nil] Call::STATUSES member ou nil se ignorar (HANDLED_REMOTELY)
  def to_call_status(external_status); end

  def terminal?(call_status); end
end
```

| Implementação | Vocabulário de entrada |
|---------------|------------------------|
| `Wavoip::Calls::StatusMapper` | Webhook: `INCOMING_RING`, `ACTIVE`, … |
| (futuro) `Whatsapp::Calls::StatusMapper` | Meta webhook statuses |

**Não** misturar vocabulário SDK (`CallStatus::CALLING`) neste mapper — isso é **porta frontend** (`callStatusUI.js`).

### 4.3 Porta `Voice::Port::CallBroadcaster`

Contrato ActionCable **provider-agnostic** (estende [webhook-contract §5](./webhook-contract.md#5-actioncable--contrato-por-provider)):

```ruby
# custom/app/services/voice/port/call_broadcaster.rb
module Voice::Port::CallBroadcaster
  def broadcast_incoming(call:, inbox:, caller:, streams:, sdp_offer: nil, ice_servers: nil)
  def broadcast_ended(call:, status:, duration_seconds: nil)
  def broadcast_accepted(call:, accepted_by_agent_id:)
  # Wavoip: sdp_offer e ice_servers sempre nil
end
```

Implementação: `Voice::Adapters::ActionCableCallBroadcaster` (única, compartilhada Meta+Wavoip) — injeta `provider:` no payload.

### 4.4 Porta `Voice::Port::CallPersistence`

Orquestra upsert sem conhecer Wavoip:

```ruby
# custom/app/services/voice/port/call_persistence.rb
module Voice::Port::CallPersistence
  # Idempotente por (provider, provider_call_id)
  def upsert_from_webhook!(inbox:, event:, mapped_status:)
  def apply_terminal_guard!(call:, new_status:)
end
```

Implementação: `Wavoip::Calls::CallUpsertService` + `CallUpdateHandler` — delegam a `Voice::InboundCallBuilder` no `CREATE` inbound.

### 4.5 Porta `Voice::Port::ConversationLinker`

**Não duplicar** `InboundCallBuilder`. Adapter fino:

```ruby
# custom/app/services/wavoip/calls/conversation_linker.rb
class Wavoip::Calls::ConversationLinker
  def self.link!(inbox:, from_phone:, external_call_id:, extra_meta: {})
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: normalize_e164(from_phone),
      call_sid: external_call_id.to_s,
      provider: :wavoip,
      extra_meta: extra_meta
    )
  end
end
```

Dependência: **inversão correta** — Wavoip depende do núcleo EE (`InboundCallBuilder`), não o contrário.

### 4.6 Porta `Voice::Port::WebhookIngress`

```ruby
# custom/app/services/voice/port/webhook_ingress.rb
module Voice::Port::WebhookIngress
  def normalize(payload); end  # → WebhookCallEvent | Array<WebhookCallEvent>
  def dispatch(normalized_event, inbox:); end
end
```

Implementação: `Wavoip::Webhooks::Dispatcher` + handlers.

### 4.7 Porta `Voice::Port::InboxResolver`

```ruby
module Voice::Port::InboxResolver
  def resolve_by_phone!(e164); end      # → Channel::Wavoip
  def resolve_by_session_id(id); end    # fallback
end
```

### 4.8 Porta `Voice::Port::RecordingAttacher`

```ruby
module Voice::Port::RecordingAttacher
  def attach_from_url!(call:, url:); end  # meta record_url + opcional download
end
```

Handler `RecordHandler` → esta porta → `Call#meta` / `Message` attachment (Fase 4).

### 4.9 `Channel::Wavoip` — contrato do aggregate

O model **só expõe** config e predicates — zero webhook/SDK:

```ruby
def voice_enabled?       # token + channel_voice
def inbound_calls_enabled?
def device_token         # coluna dedicada e protegida
def webhook_key          # nunca serializar em listagens ou logs
```

Serviços recebem `channel` injetado; não fazem `Channel::Wavoip.find` espalhado (resolver centralizado).

### 4.10 Injeção de dependências (prático Rails)

Handlers instanciados com dependências explícitas — facilita specs:

```ruby
class Wavoip::Webhooks::Handlers::CallCreateHandler
  def initialize(
    linker: Wavoip::Calls::ConversationLinker,
    broadcaster: Voice::Adapters::ActionCableCallBroadcaster.new,
    status_mapper: Wavoip::Calls::StatusMapper.new
  )
    @linker = linker
    @broadcaster = broadcaster
    @status_mapper = status_mapper
  end
end
```

Defaults no construtor; specs passam doubles. **Sem** container IoC global.

---

## 5. Contratos frontend (JavaScript)

### 5.1 Porta `BrowserVoiceSession` (substitui branching `isWhatsappCall`)

Contrato que `useCallSession` consome via registry:

```javascript
/**
 * @typedef {Object} BrowserVoiceSession
 * @property {(args: { callId: string, sdpOffer?: string, iceServers?: object[] }) => Promise<void>} acceptIncomingCall
 * @property {(callId: string) => Promise<void>} rejectIncomingCall
 * @property {(conversationId: number) => Promise<InitiateResult>} initiateOutboundCall
 * @property {(callIdOverride?: string) => Promise<void>} endActiveCall
 * @property {(muted: boolean) => boolean} setMuted
 * @property {() => void} cleanupSession
 * @property {() => boolean} hasActiveCall
 * @property {() => void} [connectForInbox] — Wavoip: ao ficar online
 * @property {() => void} [disconnect] — Wavoip: ao ficar offline
 */

/** @typedef {{ id?: number, status?: string }} InitiateResult */
```

| Provider | Implementação | SDP |
|----------|---------------|-----|
| Meta | `useWhatsappCallSession` (wrapper sobre `useWebRtcCallSession` pós-Fase 0) | Obrigatório |
| Wavoip | `useWavoipCallSession` (facade) | **Proibido** na porta |

### 5.2 Porta `VoiceCallCableHandlers`

```javascript
// custom/.../lib/voice/voiceCallCableRegistry.js
/** @type {Record<string, VoiceCallCableHandlers>} */
export const VOICE_CALL_CABLE_HANDLERS = {
  whatsapp: {
    onIncoming(data) { /* sdp_offer required */ },
    onOutboundConnected(data) { /* apply SDP */ },
    onOutboundAccepted(data) { /* arm recorder */ },
    onEnded(data) { /* local teardown guard */ },
  },
  wavoip: {
    onIncoming(data) { /* no sdp; merge store */ },
    onOutboundConnected() { /* noop */ },
    onOutboundAccepted(data) { /* setCallActive */ },
    onEnded(data) { /* teardown if local */ },
  },
};
```

`actionCable.js` — **único** `# FORK:`:

```javascript
const handler = VOICE_CALL_CABLE_HANDLERS[data?.provider];
handler?.onIncoming?.(data);
```

### 5.3 Porta `VoiceSessionRegistry` (inversão em `useCallSession`)

```javascript
// custom/.../lib/voice/voiceSessionRegistry.js
export const VOICE_SESSION_REGISTRY = {
  whatsapp: () => useWhatsappCallSession(),
  wavoip: () => useWavoipCallSession(),
  twilio: null, // conferência — caminho separado
};

export function getBrowserVoiceSession(provider) {
  const factory = VOICE_SESSION_REGISTRY[provider];
  if (!factory) return null;
  return factory();
}
```

`useCallSession.js` chama `getBrowserVoiceSession(call.provider)` — **não** importa Wavoip diretamente.

### 5.4 DTO `NormalizedCallStoreEntry` (Pinia)

Shape **único** para `FloatingCallWidget`:

```javascript
/**
 * @typedef {Object} NormalizedCallStoreEntry
 * @property {string} callSid       — provider_call_id externo
 * @property {number} [callId]      — DB id quando conhecido
 * @property {'whatsapp'|'wavoip'|'twilio'} provider
 * @property {'inbound'|'outbound'} callDirection
 * @property {number} conversationId
 * @property {number} inboxId
 * @property {boolean} isActive
 * @property {string} [sdpOffer]    — só whatsapp
 * @property {object[]} [iceServers] — só whatsapp
 * @property {{ phone: string, name?: string, avatar?: string }} [caller]
 * @property {string} [wavoipOfferId] — só wavoip; link com SDK Offer.id
 */
```

Mappers em `custom/.../lib/voice/callStoreMappers.js` (**pendente implementação** — backlog W-F2):

```javascript
export function mapCableToStoreEntry(data) {
  return {
    callSid: data.call_id,
    callId: data.id,
    provider: data.provider,
    conversationId: data.conversation_id,
    inboxId: data.inbox_id,
    callDirection: 'inbound',
    caller: data.caller,
  };
}

export function mapWavoipOfferToStoreEntry(offer, { inboxId, conversationId }) {
  return {
    callSid: offer.id,
    provider: 'wavoip',
    wavoipOfferId: offer.id,
    callDirection: 'inbound',
    inboxId,
    conversationId,
    phone: offer.peer?.phone,
    name: offer.peer?.displayName,
  };
}
```

| Origem | Mapper |
|--------|--------|
| ActionCable `voice_call.incoming` | `mapCableToStoreEntry(data)` |
| SDK `on('offer')` | `mapWavoipOfferToStoreEntry(offer, { inboxId, conversationId })` |
| `message.created` voice_call | `handleVoiceCallCreated` (existente) |

**Reconciliação:** `addCall` faz merge por `callSid`; race offer-before-webhook — ver [§3](./contracts-and-ports.md#3-fontes-da-verdade-evitar-duplicidade-conflitante) e backlog W-F3.

### 5.5 Porta `WavoipSdkPort` (isolar npm)

Único módulo que importa `@wavoip/wavoip-api`:

```javascript
// custom/.../lib/wavoip/wavoipSdkPort.js
let WavoipClass = null;

export async function loadWavoipSdk() {
  if (!WavoipClass) {
    ({ Wavoip: WavoipClass } = await import('@wavoip/wavoip-api'));
  }
  return WavoipClass;
}

export function createWavoipClient({ tokens, platform = 'chatwoot' }) {
  return new WavoipClass({ tokens, platform });
}
```

Composables dependem de `wavoipSdkPort` + `wavoipClientRegistry` — **não** de import direto (testável com mock).

### 5.6 `callStatusUI.js` — porta SDK → UI (não Rails)

```javascript
// Vocabulário SDK CallStatus → VOICE_CALL_DIRECTION / widget state
export function sdkStatusToWidgetState(callStatus) { /* ... */ }
```

Separado de `Wavoip::Calls::StatusMapper` (webhook). **Dois mappers, duas fontes** — ver [sdk-reference §7](./sdk-reference.md#7-dois-vocabulários-de-status-crítico).

---

## 6. Matriz de responsabilidades (anti god class)

| Classe / módulo | Máx. linhas | Porta / adapter | Proibido |
|-----------------|-------------|-----------------|----------|
| `WavoipController` | 40 | Transport | Parse JSON, criar Call |
| `ProcessWebhookJob` | 30 | Transport | Lógica de negócio |
| `Webhooks::Dispatcher` | 50 | Ingress | SQL |
| `PayloadNormalizer` | 120 | → DTO | Side effects |
| `CallCreateHandler` | 80 | Application | WebRTC |
| `CallUpdateHandler` | 100 | Application | `offer.accept` |
| `ConversationLinker` | 40 | → EE core | Lógica de conversa duplicada |
| `StatusMapper` | 60 | Port impl | Broadcast |
| `Broadcaster` | 80 | Port impl | Webhook parse |
| `useWavoipCallSession` | 60 | Facade | Lógica SDK inline |
| `useWavoipIncomingOffer` | 150 | Adapter | Outbound |
| `wavoipSdkPort` | 40 | Infrastructure | UI |

Se um arquivo ultrapassa o limite → extrair helper para `lib/wavoip/`.

---

## 7. Fluxos com contratos explícitos

### 7.1 Inbound (dual path)

```mermaid
sequenceDiagram
  participant SDK as Wavoip SDK
  participant WH as Webhook Handler
  participant Core as InboundCallBuilder
  participant Cable as CallBroadcaster
  participant Store as calls.js

  par Path A — tempo real
    SDK->>Store: mapWavoipOfferToStoreEntry (offer)
  and Path B — CRM
    WH->>WH: PayloadNormalizer → DTO
    WH->>Core: ConversationLinker.link!
  WH->>Cable: broadcast_incoming (sem SDP)
  Cable->>Store: mapCableToStoreEntry
  Note over Store: merge por callSid
```

### 7.2 Accept (só browser)

```mermaid
sequenceDiagram
  participant UI as FloatingCallWidget
  participant Session as BrowserVoiceSession
  participant SDK as Wavoip SDK
  participant API as PATCH calls/:id

  UI->>Session: acceptIncomingCall({ callId })
  Session->>SDK: offer.accept()
  Session->>API: accepted_by_agent_id (opcional MVP+)
  Note over SDK: Webhook ACTIVE atualiza CRM depois
```

---

## 8. Testes por contrato (quando solicitados)

| Porta | Spec | Estratégia |
|-------|------|------------|
| `PayloadNormalizer` | `spec/custom/.../payload_normalizer_spec.rb` | [fixtures/](./fixtures/) |
| `StatusMapper` | webhook vocabulary only | tabela §4.2 |
| `callStatusUI.js` | SDK vocabulary only | tabela sdk-reference §7.2 |
| `CallUpdateHandler` | terminal guard | double `CallPersistence` |
| `ConversationLinker` | delega builder | mock `InboundCallBuilder` |
| `BrowserVoiceSession` | Vitest | mock `wavoipSdkPort` |
| `voiceCallCableRegistry` | Vitest | payloads §5 webhook-contract |

**Contrato de boot:** `Call.providers` inclui `wavoip` após a edição mínima e marcada
do enum em `enterprise/app/models/call.rb`.

---

## 9. O que NÃO é porta (evitar over-engineering)

| Item | Motivo |
|------|--------|
| Interface Ruby formal para cada handler | Duck typing + specs bastam no Chatwoot |
| `Voice::OutboundWhatsappCallBuilder` no path Wavoip | Wavoip não usa `/whatsapp_calls` |
| Unificar mappers webhook + SDK num só arquivo | Vocabulários diferentes — bug garantido |
| Container DI global (dry-system) | Fora do padrão do projeto |

---

## 10. Checklist antes de codar cada fase

### Fase 1 (canal + webhook skeleton)

- [ ] DTO `WebhookCallEvent` definido
- [ ] `PayloadNormalizer` com fixtures reais
- [ ] `InboxResolver` + auth [webhook-contract §1](./webhook-contract.md#1-autenticação-http)
- [ ] Dispatcher sem lógica de domínio
- [ ] Nenhum import SDK no Rails

### Fase 2 (outbound + handlers)

- [ ] `StatusMapper` webhook-only
- [ ] `CallUpsertService` idempotente
- [ ] `ConversationLinker` → `InboundCallBuilder`
- [ ] `voiceSessionRegistry` + `wavoipSdkPort`
- [ ] `BrowserVoiceSession` implementado

### Fase 3 (inbound + widget)

- [ ] Dual path reconciliado no store
- [ ] `voiceCallCableRegistry` wavoip sem SDP
- [ ] `acceptedElsewhere` → `dismissCall`
- [ ] Device `open` gate antes de accept

### Fase 4+ (gravação, diagnóstico)

- [ ] `RecordingAttacher` porta
- [ ] `wavoipDiagnosticsCollector` isolado

---

## 11. Referência cruzada — arquivos → portas

| Arquivo `custom/` | Porta(s) |
|-------------------|----------|
| `voice/dto/webhook_call_event.rb` | DTO |
| `wavoip/webhooks/payload_normalizer.rb` | WebhookIngress (parse) |
| `wavoip/webhooks/dispatcher.rb` | WebhookIngress (dispatch) |
| `wavoip/calls/status_mapper.rb` | StatusMapper |
| `voice/adapters/action_cable_call_broadcaster.rb` | CallBroadcaster |
| `wavoip/calls/conversation_linker.rb` | ConversationLinker |
| `wavoip/calls/call_upsert_service.rb` | CallPersistence |
| `lib/voice/callStoreMappers.js` | NormalizedCallStoreEntry mappers |
| `lib/wavoip/wavoipSdkPort.js` | Infrastructure FE |
| `lib/voice/voiceSessionRegistry.js` | BrowserVoiceSession factory |
| `lib/voice/voiceCallCableRegistry.js` | VoiceCallCableHandlers |
| `composables/wavoip/useWavoipCallSession.js` | BrowserVoiceSession impl |

---

## 12. Melhorias pendentes (backlog)

Itens levantados na revisão profunda (jun/2026). A ordem executável e os gates estão
em [implementation-plan.md](./implementation-plan.md). Este §12 mantém o catálogo de
contratos por ID.

### 12.1 Integração compartilhada (após o spike)

| ID | Melhoria | Por quê | Onde implementar |
|----|----------|---------|------------------|
| W-P0.1 | Spike SDK/webhook/IDs | Confirma viabilidade antes de abstrações | [implementation-plan.md](./implementation-plan.md) Fase 0 |
| W-P0.2 | `voiceSessionRegistry` + `voiceCallCableRegistry` | `useCallSession` não deve conter branches de implementação | `custom/.../lib/voice/` + hooks mínimos |
| W-P0.3 | `isBrowserVoiceProvider()` | Evita FORK em `FloatingCallWidget`, `calls.js` | `custom/.../lib/voice/browserVoiceProviders.js` |
| W-P0.4 | Resolver imports do overlay | Adicionar alias Vite somente se a configuração atual não resolver `custom/` | Validar antes de editar `vite.shared.ts` |

`useWebRtcCallSession(callsAPI)` permanece melhoria para Meta/CPaaS com SDP e não é
pré-requisito Wavoip.

### 12.2 Backend Wavoip (Fase 1–4)

| ID | Melhoria | Detalhe |
|----|----------|---------|
| W-B1 | DTO `Voice::Dto::WebhookCallEvent` | Ruby `Data.define` — contrato §4.1 |
| W-B2 | `PayloadNormalizer` + specs com [fixtures](./fixtures/) | Campo `type` duplicado no payload Wavoip — regra defensiva aqui |
| W-B3 | `Channel::Wavoip` + migration `channel_wavoip` | Canal separado; `phone_number` único na tabela Wavoip |
| W-B4 | Enum `wavoip: 2` em `enterprise/app/models/call.rb` | Edição mínima `# FORK:`; `Call` não possui hook `prepend_mod_with` |
| W-B5 | `Voice::Adapters::ActionCableCallBroadcaster` | Porta compartilhada Meta+Wavoip (payload `provider:`) |
| W-B6 | `PATCH /api/v1/accounts/:id/calls/:id` | **Rota EE não existe hoje** — registrar `accepted_by_agent_id` após `offer.accept()`; implementar em `custom/` (Fase 3) |
| W-B7 | `Calls::AssigneeOnAcceptService` | Opcional: `conversation.assignee` ao aceitar inbound |
| W-B8 | `RecordingAttacher` | Fase 4: `record_url` → meta ou download ActiveStorage |
| W-B9 | `Channel::WavoipPolicy` | Autorização create/update/settings |
| W-B10 | Auth + throttle webhook | Chave opaca por canal; limite por chave/IP |

### 12.3 Frontend Wavoip

| ID | Melhoria | Detalhe |
|----|----------|---------|
| W-F1 | `wavoipSdkPort.js` | Único import `@wavoip/wavoip-api` |
| W-F2 | `mapWavoipOfferToStoreEntry` / `mapCableToStoreEntry` | Reconciliação dual-path inbound (§3) |
| W-F3 | Race **offer antes do webhook** | `addCall` merge por `callSid`; UI ring se só SDK; bolha quando webhook chegar |
| W-F4 | `acceptedElsewhere` / `rejectedElsewhere` | Toast + `dismissCall` |
| W-F5 | Gate `Device.status === 'open'` | Desabilitar ligar/aceitar + banner settings |
| W-F6 | `useWavoipNotifications` | OS Notification quando aba sem foco |
| W-F7 | Branch `VoiceCall.vue` | Sem join SDP; `record_url` no completed |
| W-F8 | Dynamic import SDK | Não carregar em rotas sem inbox Wavoip |
| W-F9 | Specs Vitest | Mock `wavoipSdkPort`; registry cable |

### 12.4 Produto / ops (documentar na UI)

| ID | Melhoria | Detalhe |
|----|----------|---------|
| W-O1 | Um token por inbox | Política multi-agente — [architecture §7](./architecture.md#7-multi-agente) |
| W-O2 | Sem permissão outbound Meta 138006 | UX em `peerReject` — mensagem clara |
| W-O3 | iOS Safari notifications | Só PWA — [frontend-integration §6](./frontend-integration.md#6-notificações) |
| W-O4 | `channel_wavoip` piloto | [feature-flags.md](./feature-flags.md) |
| W-O5 | i18n | **Somente `en`** no upstream (rule `chatwoot-core`); `pt_BR` só se mantido em `custom/` |

### 12.5 Melhorias Meta (não bloqueiam Wavoip, mas backlog global)

Ver [../README.md §Roadmap](../README.md#roadmap-de-melhorias-ordem-recomendada) P1–P2: adapter MetaCloud, OutboundWhatsappCallBuilder, permission service, handler `permission_granted`.

### 12.6 Critério “documentação completa”

- [x] Portas e DTOs definidos (este doc)
- [x] Fontes da verdade explícitas (§3)
- [x] Anti-patterns e limites de linhas (§6, §9)
- [x] Backlog pendente catalogado (§12)
- [ ] Payloads reais no spike substituem [fixtures](./fixtures/) templates
- [ ] Código `custom/` espelha mapa §11

As decisões de fase e go/no-go ficam em
[implementation-plan.md](./implementation-plan.md). Este documento descreve
contratos; não substitui evidência do spike.
