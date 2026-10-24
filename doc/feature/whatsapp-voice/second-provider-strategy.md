# Estratégia para segundo provider de chamadas WhatsApp

Plano para adicionar um **segundo provider de chamadas WhatsApp in-app**. **Não** usar padrão Twilio PSTN — ver [twilio-vs-whatsapp-native.md](./twilio-vs-whatsapp-native.md).

**Última reanálise:** 24 out. 2026. A Fase 0 de frontend **não** está concluída no caminho que o dashboard executa.

---

## Escolha de estratégia (decision tree)

```mermaid
flowchart TD
  START["Novo provider de voz WhatsApp"]
  START --> Q1{"API de voz expõe<br/>Meta Graph /calls<br/>ou SDP compatível?"}
  Q1 -->|Sim| META["Este documento<br/>Estender Channel::Whatsapp<br/>ou adapter Meta-like"]
  Q1 -->|Não — REST/webhook<br/>proprietário| Q1B{"SDK browser<br/>+ webhook?"}
  Q1B -->|Sim — Wavoip| WAV["wavoip-provider/README.md"]
  Q1B -->|Outro gateway| GW["Canal gateway custom/<br/>validar contrato"]
  Q1 -->|Sem API de voz| STOP["Parar — inviável"]

  style META fill:#dfd
  style WAV fill:#e3f2fd
  style GW fill:#fff3e0
  style STOP fill:#fdd
```

> **Primeiro provider alternativo no fork:** Wavoip — ver
> [wavoip-provider/README.md](./wavoip-provider/README.md), não este
> documento (focado em CPaaS Meta-like).

| Tipo de provider | Exemplos | Estratégia | Doc |
|------------------|----------|------------|-----|
| **Meta-like / CPaaS proxy** | Reseller WABA com Graph `/calls` | Adapter + reuso `/whatsapp_calls` shape | **Este doc** |
| **SDK browser + webhook** | Wavoip | Canal `Channel::Wavoip` em `custom/` | [wavoip-provider/](./wavoip-provider/) |
| **Gateway não oficial** | Evolution, Baileys, Z-API | Canal/modelo separado em `custom/` + webhook dedicado | Este doc como checklist; adaptar contrato |
| **PSTN** | Twilio, Vonage | Padrão Twilio — **não** WA in-app | [twilio-vs-whatsapp-native.md](./twilio-vs-whatsapp-native.md) |

---

## Premissas (Meta-like / CPaaS)

1. Provider expõe fluxo **WebRTC + SDP** (Meta direto ou proxy compatível offer/answer)
2. Agente continua no **dashboard browser** — mesma UX ring/accept/widget
3. Fork merge-safe: `custom/`, `prepend_mod_with`, `# FORK:` mínimos
4. Enterprise permanece obrigatório para model `Call` upstream (gateway pode viver só em `custom/` com enum próprio)

---

## Acoplamento atual que impacta o plano

| Área | Estado atual | Impacto para segundo provider |
|------|--------------|-------------------------------|
| `useWhatsappCallSession.js` | Sessão viva (~488 linhas). Não delega a `useWebRtcCallSession` | Um CPaaS SDP hoje copiaria esse arquivo, ou passaria a usar o módulo injetável |
| `WhatsappCallsController` | `#initiate` inline (~208 linhas); builder de outbound sem chamador | Extrair de novo antes de um segundo provider |
| `WhatsappCloudService` | Delega Graph `/calls` a `MetaCloud::Adapter` | Adapter deve normalizar respostas/erros |
| `WhatsappEventsJob` EE | Intercepta `field=calls` formato Meta | Payload diferente → rota/job em `custom/` |
| `actionCable.js` | `whatsappVoiceCableRegistry` + `voiceCallCableRegistry` (Wavoip) | Novo provider = entrada no registry |
| `Call.provider` | Enum `{ twilio: 0, whatsapp: 1, wavoip: 2 }` com `# FORK:` | Novo valor não pode reutilizar `2` |
| `getVoiceCallProvider()` | Twilio / WhatsApp (exceto Evolution) / Wavoip | Novo provider precisa branch/registry |

Não misturar os eixos: Twilio/PSTN usa `Voice::Provider::Twilio::*` + conferência; WhatsApp in-app usa SDP/WebRTC. Ver [twilio-vs-whatsapp-native.md](./twilio-vs-whatsapp-native.md).

### Assimetria documentada (out. 2026)

| Padrão | Twilio | WhatsApp Meta |
|--------|--------|---------------|
| Provider adapter | `Voice::Provider::Twilio::Adapter` | `Voice::Provider::MetaCloud::Adapter` |
| Outbound | `Voice::OutboundCallBuilder` | Controller inline. `Voice::OutboundWhatsappCallBuilder` sem chamador |
| Permission flow | N/A | `Whatsapp::CallPermissionRequestService` |

**Pendente:** contrato formal `Voice::Provider::WhatsappCalling::Base` (item 0.2.1). Ver [architecture-and-flow.md §13](./architecture-and-flow.md#13-roadmap-de-refatoração-melhorias-sugeridas). O plano Wavoip é independente desta trilha SDP.

---

## Fase 0 — Refactor pré-requisito para provider SDP/Meta-like

**Escopo:** esta fase é exclusiva de providers SDP/Meta-like. Para Wavoip, ver
[wavoip-provider/README.md](./wavoip-provider/README.md).

**Executar antes** de CPaaS ou qualquer segundo provider que exponha SDP compatível
com a stack Meta. Wavoip não compartilha esse core: o SDK encapsula mídia e
sinalização. Registry de sessão/eventos para Wavoip já existe (`voiceSessionRegistry`,
`voiceCallCableRegistry`).

### 0.1 Frontend (P0 — ~1 semana)

| # | Entrega | Arquivo | Done |
|---|---------|---------|------|
| 0.1.1 | Módulo `useWebRtcCallSession` | `composables/useWebRtcCallSession.js` | Existe (~525 linhas) e não é o caminho dos botões |
| 0.1.2 | `useWhatsappCallSession` vira thin wrapper | mesmo path | **Aberto** — ~488 linhas, API WhatsApp direta |
| 0.1.3 | `BROWSER_VOICE_PROVIDERS` | `custom/.../lib/voice/browserVoiceProviders.js` | Set com `whatsapp` e `wavoip`; não é registry de sessão |
| 0.1.4 | Registry em `useCallSession` | `composables/useCallSession.js` | Parcial — registries cable; facade ainda brancha |
| 0.1.5 | Generalizar filtro cable | `whatsappVoiceCableRegistry.js` + `voiceCallCableRegistry.js` | Feito |
| 0.1.6 | Specs Vitest (race, 422, beacon) | `composables/spec/useWebRtcCallSession.spec.js` | Cobrem o módulo paralelo, não a sessão viva |

### 0.2 Backend (P1 — ~1 semana, opcional antes de CPaaS)

| # | Entrega | Arquivo | Done |
|---|---------|---------|------|
| 0.2.1 | Contrato `Voice::Provider::WhatsappCalling::Base` | `enterprise/.../whatsapp_calling/base.rb` | **Pendente** — único item BE Fase 0 restante |
| 0.2.2 | `Voice::Provider::MetaCloud::Adapter` | `enterprise/.../meta_cloud/adapter.rb` | ✅ Done (jul. 2026) |
| 0.2.3 | Prepend delega ao adapter | `WhatsappCloudService` EE | ✅ Done (jul. 2026) |
| 0.2.4 | `Voice::OutboundWhatsappCallBuilder` no `#initiate` | `enterprise/.../outbound_whatsapp_call_builder.rb` | Classe e spec existem; controller não chama |
| 0.2.5 | `Whatsapp::CallPermissionRequestService` | `enterprise/.../call_permission_request_service.rb` | ✅ Done (jun. 2026) |
| 0.2.6 | Specs espelhados | `spec/enterprise/services/...` | Builders + permission service |

### 0.3 Critérios de saída Fase 0

- [ ] `useWhatsappCallSession.js` < 80 linhas (hoje ~488)
- [ ] Zero regressão Meta inbound/outbound em staging
- [ ] `rg isWhatsappCall` — branching reduzido a registry (parcial — registries cable prontos)
- [ ] Novo provider WebRTC = novo wrapper + entrada no registry (sem copiar WebRTC core)

**Wavoip:** não depende de 0.1.1–0.1.2 nem de 0.2. Já usa dispatch
provider-agnostic em registries + `useWavoipCallSession` — ver
[wavoip-provider/architecture.md](./wavoip-provider/architecture.md).

---

## Arquitetura alvo

```mermaid
flowchart TB
    subgraph FE
        UCS[useCallSession]
        WEB[useWebRtcCallSession<br/>api injetável]
        UCS --> WEB
    end

    subgraph BE
        Ctrl[WhatsappCallsController]
        Adp1[MetaCloudAdapter — atual ✅]
        Adp2[CustomCpaasAdapter — custom/]
        Ctrl --> Adp1 & Adp2
    end

    subgraph Channel
        Ch1[Whatsapp provider=whatsapp_cloud]
        Ch2[Whatsapp provider=custom_cpaas]
    end

    Ch1 --> Adp1
    Ch2 --> Adp2
```

**Ideia:** manter shape de `useWhatsappCallSession` e `WhatsappCallsController`; extrair Meta-specific para adapters.

---

## Fase 1 — Adapter de sinalização (backend)

### 1.1 Contrato mínimo

```ruby
# enterprise/app/services/voice/provider/whatsapp_calling/base.rb
# (ou custom/ se fork não contribuir upstream)
module Voice::Provider::WhatsappCalling::Base
  def initiate_call(to_phone, sdp_offer); end
  def pre_accept_call(call_id, sdp_answer); end
  def accept_call(call_id, sdp_answer); end
  def reject_call(call_id); end
  def terminate_call(call_id); end
  def send_call_permission_request(to_phone, body_text = nil); end
  def update_calling_status(status); end
end
```

Implementações:

| Classe | Provider |
|--------|----------|
| `Voice::Provider::MetaCloud::Adapter` | `whatsapp_cloud` (atual) |
| `Voice::Provider::CustomCpaas::Adapter` | `custom_cpaas` (fork) |

### 1.2 Implementação Meta atual

Extrair de `Enterprise::Whatsapp::Providers::WhatsappCloudService` para `Voice::Provider::MetaCloud::Adapter`. O prepend de `WhatsappCloudService` delega:

```ruby
def initiate_call(to_phone, sdp_offer)
  meta_cloud_adapter.initiate_call(to_phone, sdp_offer)
end

def meta_cloud_adapter
  @meta_cloud_adapter ||= Voice::Provider::MetaCloud::Adapter.new(whatsapp_channel)
end
```

**Não** deixar HTTP Meta espalhado no controller — só no adapter (camada infrastructure).

### 1.3 Dispatch por provider

```ruby
# Pseudocódigo — custom/ prepend Channel::Whatsapp
def whatsapp_calling_adapter
  case provider
  when 'whatsapp_cloud' then Voice::Provider::MetaCloud::Adapter.new(self)
  when 'custom_cpaas'   then Voice::Provider::CustomCpaas::Adapter.new(self)
  else raise "Calling not supported for #{provider}"
  end
end

def voice_calling_supported?
  %w[whatsapp_cloud custom_cpaas].include?(provider)
end
```

Normalizar erros de permissão para código equivalente ao **138006** (`Voice::CallErrors::NO_CALL_PERMISSION_CODE`).

### 1.4 Webhooks

| Opção | Quando |
|-------|--------|
| **A.** Prepend `WhatsappEventsJob` roteando por provider | CPaaS reenvia payload Meta `field=calls` |
| **B.** Job + rota webhook dedicada em `custom/` | Payload diferente — **preferir** para não inflar job |

Serviços espelhados:

- `IncomingCallService` → mesma saída (`InboundCallBuilder`)
- `CallService` → adapter injetado

---

## Fase 2 — API REST

### Opção mínima (recomendada fork)

- Manter rotas `/whatsapp_calls`
- Controller usa `channel.whatsapp_calling_adapter` (ou `provider_service` estendido)
- Novo provider = novo valor em `Channel::Whatsapp.provider`
- Whitelist de provider exige `# FORK:` mínimo em `Channel::Whatsapp::PROVIDERS` (a validação usa constante congelada)

### Opção limpa (maior diff)

- Renomear para `/voice_calls` — só se valer refactor amplo

**Arquivos:**

- `whatsapp_calls_controller.rb` — injeção adapter; `initiate` → `OutboundWhatsappCallBuilder`
- `incoming_call_service.rb` — provider-agnostic via adapter injetado, ou duplicar fino em `custom/`
- `call_service.rb` — `invoke_provider!` → `channel.whatsapp_calling_adapter`

---

## Fase 3 — Frontend

### Shape a preservar (`useWhatsappCallSession`)

| Comportamento | Manter |
|---------------|--------|
| `prepareInboundAnswer` / `prepareOutboundOffer` | ✅ |
| `acceptIncomingCall` / `initiateOutboundCall` | ✅ |
| `applyOutboundAnswer` + `pendingOutboundAnswers` | ✅ |
| `armOutboundRecorder` | ✅ |
| Beacon terminate (`pagehide`) | ✅ |
| Estados `permission_requested` / `permission_pending` | ✅ se CPaaS tiver opt-in |

### Refactor sugerido (alvo — não é o código de out. 2026)

```
composables/useWebRtcCallSession.js      — único RTCPeerConnection + callsAPI injetável
composables/useWhatsappCallSession.js    — wrapper WhatsappCallsAPI
custom/.../useWavoipCallSession.js       — sessão SDK, sem SDP Meta
helper/voiceCallProviders.js             — registry cable/session
```

### Handler `voice_call.permission_granted` (P2)

Adicionar em `actionCable.js` após generalizar filtro:

```javascript
onVoiceCallPermissionGranted = data => {
  // Toast: contato autorizou — agente pode retentar outbound
  useAlert(t('CONVERSATION.WHATSAPP_CALL.PERMISSION_GRANTED', { name: data.contact_name }));
};
```

### `useCallSession.js`

```javascript
const WEBRTC_PROVIDERS = [VOICE_CALL_PROVIDERS.WHATSAPP, VOICE_CALL_PROVIDERS.CUSTOM_CPAAS];
// registry[provider] em vez de isWhatsappCall only
```

### `actionCable.js`

Reusar `voice_call.*` — estender filtro:

```javascript
// FORK: aceitar múltiplos providers WebRTC
if (!WEBRTC_PROVIDERS.includes(data?.provider)) return;
```

### UI

| Arquivo | Mudança |
|---------|---------|
| `ConversationCallButton.vue` | `isWebRtcVoiceInbox(inbox)` |
| `WhatsappCallingPage.vue` | Seção por provider ou duplicar settings |
| `ChannelList` / signup | Flag no provider existente vs tile separado |

---

## Fase 4 — Modelo e gates

```ruby
# Call enum — enterprise/app/models/call.rb
# wavoip: 2 já está ocupado (# FORK:). O próximo valor é 3.
enum :provider, { twilio: 0, whatsapp: 1, wavoip: 2, custom_cpaas: 3 }
```

Feature: reusar `channel_voice`; opcional flag rollout `channel_voice_custom_cpaas`.

---

## Mapa de arquivos (`custom/` preferido)

| Arquivo | Responsabilidade |
|---------|------------------|
| `custom/app/services/voice/provider/custom_cpaas/adapter.rb` | API CPaaS |
| `custom/app/services/custom_cpaas/incoming_call_service.rb` | Webhook → builders |
| `custom/app/controllers/webhooks/custom_cpaas/calls_controller.rb` | Webhook |
| `custom/app/models/custom/channel/whatsapp.rb` | Adapter dispatch |
| `custom/.../useCustomCpaasCallSession.js` | Wrapper WebRTC |
| `custom/.../customCpaasCallsAPI.js` | HTTP client |

### Edições `# FORK:` (se inevitável)

| Arquivo | Hook |
|---------|------|
| `app/models/channel/whatsapp.rb` | `PROVIDERS` com `# FORK:` mínimo |
| `inbox.js` | `getVoiceCallProvider` |
| `useCallSession.js` | registry WebRTC |
| `actionCable.js` | filtro provider |
| `config/routes.rb` | webhook CPaaS |

### Reuso sem alteração

- `Voice::InboundCallBuilder`, `CallMessageBuilder`
- `FloatingCallWidget`, `calls.js` (com case teardown)
- ActionCable event names (`voice_call.*`)

---

## Ordem de implementação

0. **Fase 0 refactor** — `useWebRtcCallSession` + registry (para provider SDP/Meta-like)
1. **Adapter + webhook inbound** — connect SDP → ring widget
2. **Accept/terminate** — loop WebRTC fechado
3. **Outbound initiate** — offer + answer via cable
4. **Permissão outbound** — se CPaaS/Meta exigir (+ handler FE `permission_granted`)
5. **Settings + enable calling**
6. **Gravação upload**

---

## Estimativa

| Escopo | Tempo |
|--------|-------|
| **Fase 0** refactor FE (extrair WebRTC + registry) | **~1 semana** |
| **Fase 0** refactor BE (adapter + builders + permission service) | **~1 semana** (opcional antes de Wavoip) |
| CPaaS API idêntica Meta (proxy) | **2–3 semanas** (após Fase 0) |
| Payload webhook diferente | **3–5 semanas** (após Fase 0) |
| Wavoip (canal separado) | Ver [wavoip-provider/README.md](./wavoip-provider/README.md) |

---

## Anti-padrões

1. Forçar payload diverso no `WhatsappEventsJob` sem normalizer
2. Reusar `Channel::TwilioSms` para WA Calling
3. Duplicar as ~488 linhas de `useWhatsappCallSession` em outro provider SDP. O módulo injetável já existe e o caminho vivo não o usa
4. Editar `enterprise/` upstream sem espelhar em `custom/`
5. Novo channel model se o contrato ainda for apenas outra variante de `Channel::Whatsapp`
6. Deixar lógica de permissão outbound no controller — extrair `CallPermissionRequestService`
7. Integrar um provider ao widget sem antes definir dispatch por provider
8. Inflar model `Call` upstream com campos de um só provider — usar `meta` jsonb; novos valores de enum exigem alteração explícita e estável
9. God module FE — misturar WebRTC core com API específica de provider no mesmo arquivo
10. Ignorar TURN em deploy corporativo — `VOICE_CALL_ICE_SERVERS` (JSON com credencial) em `Custom::Call`; a offer outbound do browser ainda fixa o STUN do Google

---

## Critérios de pronto

### Fase 0 (refactor)

- [ ] `useWebRtcCallSession` é o único core; `useWhatsappCallSession` < 80 linhas
- [x] Registry provider em cable (`whatsappVoiceCableRegistry` + `voiceCallCableRegistry`)
- [ ] Specs Vitest de race buffer e permission 422 na sessão que os botões usam
- [ ] Sem regressão `whatsapp_cloud` em inbound/outbound/terminate

### Segundo provider

- [ ] Inbound: ring → accept → áudio bidirecional
- [ ] Outbound: initiate → SDP → contato atende no WhatsApp
- [ ] Terminate local/remoto limpa WebRTC + mensagem `voice_call`
- [ ] `Call.provider` correto
- [ ] Opt-in outbound (se aplicável) + handler `permission_granted` (se Meta-like)
- [ ] Sem regressão `whatsapp_cloud`
- [ ] `rg "FORK:"` documentado
- [ ] TURN documentado para admins se deploy corporativo

---

## Referência cruzada

- Fluxo Meta atual: [architecture-and-flow.md](./architecture-and-flow.md)
- Twilio/PSTN não substitui WA in-app: [twilio-vs-whatsapp-native.md](./twilio-vs-whatsapp-native.md)
- Gateway não Meta-like: validar contrato próprio de voz antes de implementar UI
- Mensagens gateway: [whatsapp-provider/README.md](../whatsapp-provider/README.md)
