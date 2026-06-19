# Caixa de entrada Wavoip — setup na criação

Especificação do fluxo **Configurações → Caixas de Entrada → novo tile → Criar caixa
de entrada**. A criação coleta identidade e token; a ativação do webhook ocorre depois
que o backend gerar a URL.

**UI de referência:** slot vazio na grade de canais (ao lado de “Chamada WhatsApp” Meta).

**Relacionado:** [contracts-and-ports.md](./contracts-and-ports.md) · [implementation-plan.md](./implementation-plan.md) · [architecture.md](./architecture.md) · [frontend-integration.md](./frontend-integration.md) · [sdk-reference.md](./sdk-reference.md) · [official-docs.md](./official-docs.md)

---

## 1. Fluxo do wizard

```mermaid
flowchart LR
  S1["1. Escolha o canal<br/>tile Wavoip"]
  S2["2. Criar caixa de entrada<br/>identidade + token"]
  S3["3. Ativar webhook<br/>copiar URL e validar"]
  S4["4. Adicionar agentes"]
  S5["5. Pronto"]

  S1 --> S2 --> S3 --> S4 --> S5
```

| Passo | Componente | Responsabilidade |
|-------|------------|------------------|
| 1 | `ChannelList.vue` + `ChannelItem.vue` | Tile `wavoip` (Beta), gate `channel_voice` |
| 2 | `custom/.../channels/Wavoip.vue` | Formulário com todos os campos abaixo |
| 3 | `WavoipWebhookInstructions.vue` | Configurar URL e aguardar primeiro evento |
| 4 | Rota `settings_inboxes_add_agents` | Igual aos demais canais |
| 5 | Dashboard | Inbox operacional após agentes adicionados |

**Não** usar `@wavoip/wavoip-webphone` no passo 2 — apenas formulário Vue + API Rails.

---

## 2. Tile na grade de canais

| Propriedade | Valor |
|-------------|-------|
| `key` | `wavoip` |
| `icon` | `i-woot-whatsapp` (ou ícone dedicado fork) |
| `title` (i18n) | `INBOX_MGMT.ADD.AUTH.CHANNEL.WAVOIP.TITLE` — ex.: “Chamada Wavoip” |
| `description` | `INBOX_MGMT.ADD.AUTH.CHANNEL.WAVOIP.DESCRIPTION` |
| `isBeta` | `true` |
| `isActive` | `enabledFeatures.channel_voice` && (`channel_wavoip` se em piloto) |

Registro em `ChannelFactory.vue` (`# FORK:`):

```javascript
wavoip: Wavoip, // import from custom/
```

---

## 3. Campos do formulário (passo 2)

O setup tem duas etapas: criar o inbox e depois ativar o webhook. A URL contém uma
chave gerada pelo backend e só existe após a criação. Pareamento completo por QR/código
fica pós-MVP; inicialmente o admin pode operar o dispositivo no painel Wavoip.

### 3.1 Seção — Identidade da caixa

| Campo | API / storage | Obrigatório | Validação | Notas |
|-------|---------------|-------------|-----------|-------|
| **Nome da caixa de entrada** | `inbox.name` | Não | max 255 | Default: `Wavoip ({phone_number})` se vazio |
| **Número WhatsApp** | `channel.phone_number` | Sim | E.164 (`isPhoneE164`) | Único entre canais Wavoip; pode coexistir com inbox de mensagens |

### 3.2 Seção — Dispositivo Wavoip

Dados obtidos em [app.wavoip.com/devices](https://app.wavoip.com/devices) — ver
[Vincule um Whatsapp](https://wavoip.gitbook.io/api/dispositivo/vincule-um-whatsapp.md)
e [official-docs.md](./official-docs.md).

| Campo | Storage | Obrigatório | Validação | Notas |
|-------|----------------------|-------------|-----------|-------|
| **Token do dispositivo** | coluna `device_token` | Sim | present, min length | `type="password"`; criptografado quando disponível; nunca entra em listagens |
| **ID da sessão** | `provider_config.id_session` | Não | integer opcional | Cache de validação/correlação; não resolve autenticação do webhook |

Referência SDK: [`new Wavoip({ tokens: [...] })`](https://wavoip.gitbook.io/api/wavoip-api/primeiros-passos/initialization.md).

### 3.3 Seção — Comportamento de chamadas

| Campo | `provider_config` key | Obrigatório | Default | Mapeamento Wavoip |
|-------|----------------------|-------------|---------|-------------------|
| **Aceitar chamadas recebidas** | `inbound_calls_enabled` | Não | `true` | Se `false`, SDK ignora offers + webhook registra missed |
| **Identificador da plataforma** | `platform` | — | `'chatwoot'` | Fixo no backend; repassado ao `new Wavoip({ platform })` |

### 3.4 Ativação — webhook do servidor

Exibida **após** o inbox ser criado. O admin configura a URL no painel Wavoip
(**Integrações → Webhook**) e o Chatwoot marca a integração como validada ao receber o
primeiro evento autenticado.

| Campo | Storage | Comportamento |
|-------|---------|---------------|
| **URL do webhook** | derivada de `webhook_key` | `{FRONTEND_URL}/webhooks/wavoip/{opaque_key}` |
| **Rotacionar URL** | gera nova chave | Invalida a anterior e exige atualizar o painel |
| **Status** | `pending` / `verified` | `verified` após primeiro webhook válido |

Referência: [Webhook (Beta)](https://wavoip.gitbook.io/api/webhook-beta.md) ·
contrato auth [webhook-contract.md](./webhook-contract.md).

### 3.5 Seção — Notificações do agente (opcional, colapsada)

Comportamento espelhado da [doc de notificações push](https://wavoip.gitbook.io/api/webphone/recursos/notificacoes-push.md), implementado no Chatwoot (`useWavoipNotifications`), não no webphone.

| Campo | `provider_config` key | Default |
|-------|----------------------|---------|
| **Notificar quando aba em segundo plano** | `offer_notification_enabled` | `true` |
| **Ícone da notificação (URL)** | `offer_notification_icon` | logo da instalação |

Permissão `Notification` continua sendo pedida no gesto “ficar online” (não no formulário de criação — browsers bloqueiam prompt sem gesto).

---

## 4. Layout do formulário (wireframe lógico)

```
┌─────────────────────────────────────────────────────────┐
│ Chamada Wavoip                                          │
│ Integre chamadas de voz WhatsApp via Wavoip.            │
├─────────────────────────────────────────────────────────┤
│ Identidade                                                │
│   [ Nome da caixa de entrada        ]                     │
│   [ Número WhatsApp (E.164)         ] *                   │
├─────────────────────────────────────────────────────────┤
│ Dispositivo Wavoip                                        │
│   [ Token do dispositivo            ] *  (password)       │
│   [ ID da sessão (opcional)         ]                     │
│   ℹ️ Crie o dispositivo em app.wavoip.com/devices         │
├─────────────────────────────────────────────────────────┤
│ Chamadas                                                  │
│   [x] Aceitar chamadas recebidas                          │
├─────────────────────────────────────────────────────────┤
│ Webhook                                                   │
│   URL disponível após criar o inbox.                      │
│   O próximo passo orientará a configuração no Wavoip.     │
├─────────────────────────────────────────────────────────┤
│ ▼ Notificações (opcional)                                 │
│   [x] Notificar agente com aba em segundo plano           │
├─────────────────────────────────────────────────────────┤
│                              [ Criar caixa de entrada ]   │
└─────────────────────────────────────────────────────────┘
```

Componentes Vue sugeridos (evitar god component):

| Componente | Responsabilidade |
|------------|------------------|
| `Wavoip.vue` | Orquestra submit + navegação |
| `WavoipInboxIdentityFields.vue` | Nome + telefone |
| `WavoipDeviceFields.vue` | Token + id_session |
| `WavoipCallBehaviorFields.vue` | inbound toggle |
| `WavoipWebhookInstructions.vue` | URL pós-criação, copy, rotação e status de verificação |
| `WavoipNotificationFields.vue` | Campos opcionais colapsados |

---

## 5. Payload de criação

### 5.1 Frontend → API

```javascript
await store.dispatch('inboxes/createWavoipChannel', {
  name: state.inboxName || `Wavoip (${state.phoneNumber})`,
  wavoip: {
    phone_number: state.phoneNumber,
    device_token: state.deviceToken,
    provider_config: {
      id_session: state.idSession || null,
      inbound_calls_enabled: state.inboundCallsEnabled,
      offer_notification_enabled: state.offerNotificationEnabled,
      offer_notification_icon: state.offerNotificationIcon || null,
      platform: 'chatwoot',
    },
  },
});
```

### 5.2 Store action (`custom/` ou `# FORK:` em `channelActions.js`)

```javascript
createWavoipChannel: async ({ commit }, params) => {
  const response = await InboxesAPI.create({
    name: params.name,
    channel: { ...params.wavoip, type: 'wavoip' },
  });
  // ...
};
```

### 5.3 Backend — strong params

```ruby
# custom/.../enterprise/inboxes_controller.rb (prepend)
def create_wavoip_channel
  raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('channel_voice')

  wavoip_params = params.require(:channel).permit(
    :phone_number,
    :device_token,
    provider_config: [
      :id_session,
      :inbound_calls_enabled,
      :offer_notification_enabled,
      :offer_notification_icon
    ]
  )

  config = wavoip_params[:provider_config] || {}
  config['platform'] = 'chatwoot'
  config['inbound_calls_enabled'] = config.fetch('inbound_calls_enabled', true)

  Current.account.channel_wavoip.create!(
    phone_number: wavoip_params[:phone_number],
    device_token: wavoip_params[:device_token],
    provider_config: config
  )
end
```

Validação em service dedicado (não no model):

```ruby
# custom/app/services/wavoip/channels/create_validator.rb
class Wavoip::Channels::CreateValidator
  def initialize(phone_number:, device_token:)
    @phone_number = phone_number
    @device_token = device_token
  end

  def validate!
    raise ArgumentError, 'device_token required' if @device_token.blank?
    raise ArgumentError, 'invalid phone' unless phone_e164?(@phone_number)
  end
end
```

### 5.4 Resposta API (inbox criado)

Incluir na serialização do inbox (somente para admins da conta):

```json
{
  "webhook_url": "https://app.example.com/webhooks/wavoip/opaque-random-key",
  "webhook_configured": false
}
```

`webhook_url` só é exibida após o backend criar o canal e gerar `webhook_key`.

---

## 6. Pós-criação imediato

Após `POST /inboxes` bem-sucedido:

1. Exibir a etapa de ativação com URL, botão copiar e status `pending`.
2. Após confirmação do admin, navegar para `settings_inboxes_add_agents`.
3. **Não** conectar o SDK neste passo — conexão só quando agente autorizado ficar
   **online** (ver [frontend-integration.md](./frontend-integration.md)).

---

## 7. Settings (edição posterior)

No MVP, a tab **Chamadas** expõe token, toggles, URL/status do webhook e estado básico
do device. Pareamento e ações administrativas completas ficam pós-MVP:

| Painel | SDK | Quando mostrar |
|--------|-----|----------------|
| Status do dispositivo | `device.status`, `statusChanged` | Sempre |
| QR code | `qrCodeChanged` | `status === 'connecting'` |
| Código de pareamento | `pairingCode(phone)` | Alternativa ao QR |
| Acordar | `wakeUp()` | `hibernating` |
| Reiniciar / logout | `restart()`, `logout()` | Admin troubleshooting |

Detalhes: [sdk-reference.md §2](./sdk-reference.md#2-dispositivo-device).

**`WavoipOnboardingChecklist`:** semáforo 6 passos — [operations-runbook.md](./operations-runbook.md#checklist-de-onboarding-semáforo).

Campos editáveis:

| Campo | Editável após criar? |
|-------|----------------------|
| `phone_number` | Não (recreate inbox) |
| `device_token` | Sim (rotacionar token) |
| toggles e notification | Sim |
| `webhook_key` | Rotação por ação dedicada; nunca aceitar valor escolhido pelo cliente |
| `webhook_url` | Read-only (derivada da chave) |

---

## 8. i18n

Seguir a regra do projeto: atualizar somente inglês nos arquivos upstream. Traduções
adicionais pertencem ao overlay do fork, se ele optar por mantê-las.

Chaves sugeridas:

```json
{
  "INBOX_MGMT": {
    "ADD": {
      "AUTH": {
        "CHANNEL": {
          "WAVOIP": {
            "TITLE": "Wavoip Call",
            "DESCRIPTION": "Receive and place WhatsApp voice calls via Wavoip"
          }
        }
      },
      "WAVOIP": {
        "TITLE": "Wavoip Voice Channel",
        "DESC": "Connect your Wavoip device to handle WhatsApp voice calls.",
        "INBOX_NAME": { "LABEL": "Inbox name", "PLACEHOLDER": "Support (Wavoip)" },
        "PHONE_NUMBER": { "LABEL": "WhatsApp number", "PLACEHOLDER": "+5511999999999", "ERROR": "..." },
        "DEVICE_TOKEN": { "LABEL": "Device token", "PLACEHOLDER": "...", "HELP": "From app.wavoip.com/devices" },
        "ID_SESSION": { "LABEL": "Session ID (optional)", "PLACEHOLDER": "12345" },
        "INBOUND_ENABLED": { "LABEL": "Accept incoming calls" },
        "WEBHOOK": {
          "TITLE": "Webhook",
          "URL_LABEL": "Webhook URL",
          "COPY_URL": "Copy URL",
          "HELP": "Paste the URL in Wavoip → Device → Integrations → Webhook",
          "PENDING": "Waiting for the first webhook event",
          "VERIFIED": "Webhook verified"
        },
        "NOTIFICATIONS": {
          "TITLE": "Agent notifications",
          "ENABLED": "Notify when tab is in background"
        },
        "SUBMIT_BUTTON": "Create Wavoip inbox",
        "API": { "ERROR_MESSAGE": "Could not create the Wavoip inbox" }
      }
    }
  }
}
```

---

## 9. Diferença vs tile “Chamada WhatsApp” (Meta)

| | Meta `whatsapp_call` | Wavoip `wavoip` |
|--|----------------------|-----------------|
| Gate UI | `channel_voice` + `whatsappAppId` | `channel_voice` apenas |
| Passo 2 | Embedded signup Meta | Formulário manual (este doc) |
| Credencial | WABA / Cloud API | Token dispositivo Wavoip |
| Webhook | Meta → `/webhooks/whatsapp` | Wavoip → `/webhooks/wavoip/:webhook_key` |

Os dois tiles podem aparecer na mesma grade; são produtos paralelos.

---

## 10. Critérios de done (setup inbox)

- [ ] Tile `wavoip` visível com `channel_voice` habilitada
- [ ] Formulário valida E.164 + token obrigatório
- [ ] `Channel::Wavoip` criado com `provider_config` completo
- [ ] `webhook_key` opaca gerada pelo backend
- [ ] Pós-criação mostra URL e status de verificação
- [ ] Redirect para adicionar agentes
- [ ] Settings permitem editar token e toggles
- [ ] Nenhum dado sensível em `window.chatwootConfig` global
