# Qualidade de código — Wavoip

Duplicações de lógica, estado global problemático e problemas de performance identificados
na revisão. Não quebram o fluxo feliz, mas aumentam o custo de manutenção e podem se
transformar em bugs quando a codebase crescer.

---

## QC-01 · `mark_webhook_verified!` duplicado em dois serviços

**Categoria:** DRY  
**Arquivos:**
- `custom/app/services/wavoip/calls/call_upsert_service.rb` (linhas 97–105)
- `custom/app/services/wavoip/calls/handled_remotely_stub_service.rb` (linhas 65–73)

### Descrição

O método privado `mark_webhook_verified!` é idêntico nos dois serviços:

```ruby
def mark_webhook_verified!
  channel = inbox.channel
  return unless channel.is_a?(Channel::Wavoip)
  return if channel.webhook_verified?

  config = (channel.provider_config || {}).dup
  config['webhook_verified_at'] = Time.current.iso8601
  channel.update!(provider_config: config)
end
```

Qualquer mudança (ex: adicionar `verified_by` ao config) exige edição em dois lugares.
Há também uma race condition latente: sem `with_lock`, dois webhooks concorrentes que
chegam antes da verificação passam no `channel.webhook_verified?` e tentam ambos o `update!`.

### Correção

Mover para `Channel::Wavoip#mark_webhook_verified!` com lock otimista:

```ruby
# channel/wavoip.rb
def mark_webhook_verified!
  return if webhook_verified?
  with_lock do
    reload
    return if webhook_verified?
    config = (provider_config || {}).dup
    config['webhook_verified_at'] = Time.current.iso8601
    update!(provider_config: config)
  end
end
```

Os dois serviços chamam `inbox.channel.mark_webhook_verified!`.

---

## QC-02 · `update_conversation` duplicado em dois serviços

**Categoria:** DRY  
**Arquivos:**
- `custom/app/services/wavoip/calls/call_status_applier.rb` (linhas 126–133)
- `custom/app/services/wavoip/calls/handled_remotely_stub_service.rb` (linhas 56–63)

### Descrição

```ruby
# idêntico nos dois serviços
def update_conversation(call)
  call.conversation.update!(
    additional_attributes: (call.conversation.additional_attributes || {}).merge(
      'call_status' => call.display_status,
      'call_direction' => call.direction_label
    )
  )
end
```

`HandledRemotelyStubService` bypassa `CallStatusApplier` inteiramente, criando um caminho
paralelo de manutenção. Adicionar um novo campo (ex: `call_ended_at`) exigiria edição nos
dois lugares.

### Correção

Extrair para o model `Call` ou um concern compartilhado:

```ruby
# custom/app/models/custom/call.rb
module Custom::Call
  def sync_conversation_call_attributes!
    conversation.update!(
      additional_attributes: (conversation.additional_attributes || {}).merge(
        'call_status' => display_status,
        'call_direction' => direction_label
      )
    )
  end
end
```

Ambos os serviços chamam `call.sync_conversation_call_attributes!`.

---

## QC-03 · `call.reload` redundante dentro de `with_lock`

**Categoria:** Código desnecessário  
**Arquivos:**
- `custom/app/services/wavoip/calls/call_status_applier.rb` (linha 35)
- `custom/app/controllers/api/v1/accounts/calls_controller.rb` (linha 23)

### Descrição

`ActiveRecord#with_lock` já chama `lock!` internamente, que recarrega o registro com lock.
O `call.reload` explícito logo após é redundant e enganoso — sugere que o desenvolvedor
não confiou que `with_lock` já recarregou:

```ruby
# call_status_applier.rb
def apply_locked!(call, mapped_status, broadcast:)
  call.reload   # ← redundante: with_lock já recarregou
```

```ruby
# calls_controller.rb
@call.with_lock do
  @call.reload  # ← redundante
```

### Correção

Remover os `reload` explícitos. Adicionar comentário se a intenção precisar ser documentada:
```ruby
# with_lock recarrega o registro — não é necessário reload explícito
@call.with_lock do
  next if @call.accepted_by_agent_id.present?
```

---

## QC-04 · `channel_type` como string literal vs constante `INBOX_TYPES`

**Categoria:** Inconsistência  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipCallSession.js` (linha 90)

### Descrição

```js
// useWavoipCallSession.js
inbox.channel_type === 'Channel::Wavoip'   // ← string literal
```

Em todos os outros pontos do codebase usa-se a constante:
```js
// useWavoipConnection.js
const isWavoipInbox = inbox => inbox?.channel_type === INBOX_TYPES.WAVOIP;
```

Se `INBOX_TYPES.WAVOIP` mudar de valor (improvável, mas possível), a comparação literal
em `useWavoipCallSession.js` se tornaria um bug silencioso.

### Correção

```js
import { INBOX_TYPES } from 'dashboard/helper/inbox';
// ...
inbox.channel_type === INBOX_TYPES.WAVOIP
```

---

## QC-05 · Variável `normalized` morta em `ProcessWebhookJob`

**Categoria:** Código morto  
**Arquivo:** `custom/app/jobs/wavoip/process_webhook_job.rb` (linha 13)

### Descrição

```ruby
def perform(inbox_id, payload)
  # ...
  normalized = payload.with_indifferent_access   # ← criado aqui
  result = Wavoip::Webhooks::Dispatcher.new(inbox: inbox, payload: payload).dispatch
  #                                                                 ↑ payload original, não normalized
  Rails.logger.info("... type=#{normalized[:type]} ...")  # ← único uso
end
```

O `Dispatcher` recebe `payload` (original), não `normalized`. A variável existe apenas
para o log no final — o que é enganoso: parece que `normalized` está sendo passado.

### Correção

```ruby
def perform(inbox_id, payload)
  # ...
  result = Wavoip::Webhooks::Dispatcher.new(inbox: inbox, payload: payload).dispatch
  log_payload = payload.with_indifferent_access
  Rails.logger.info("... type=#{log_payload[:type]} ...")
end
```

Ou simplificar ainda mais usando `payload` diretamente no log (já é `HashWithIndifferentAccess`
após `to_unsafe_hash` no controller).

---

## QC-06 · `assignee_scope` executado duas vezes por query em `assignee_or_fallback`

**Categoria:** Performance  
**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb` (linhas 75–77)

### Descrição

```ruby
def assignee_or_fallback(fallback_scope)
  assignee_scope.exists? ? assignee_scope : fallback_scope
end
```

`assignee_scope` é um método que retorna uma nova `ActiveRecord::Relation` a cada chamada.
A ternária executa `.exists?` em uma relation e depois retorna **outra** relation recém-criada
— duas queries SQL para o mesmo dado.

Isso ocorre em toda chamada entrante que passa pelo fallback (potencialmente a maioria
das chamadas quando não há agentes online).

### Correção

```ruby
def assignee_or_fallback(fallback_scope)
  scope = assignee_scope
  scope.exists? ? scope : fallback_scope
end
```

---

## QC-07 · `busy_agents` carrega todos os usuários da conta do Redis para Ruby

> **Status (26 jun. 2026):** ✅ Implementado — `OnlineStatusTracker.get_users_with_status`
> faz `hmget` apenas para `recipients_base_scope.ids` (após interseção com presença).
> Usado em `online_member_users` e `busy_agents`.

**Categoria:** Performance  
**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

### Descrição

```ruby
def busy_agents
  busy_ids = OnlineStatusTracker.get_available_users(inbox.account_id)
                                .select { |_key, value| value == 'busy' }
                                .keys
                                .map(&:to_i)
  recipients_base_scope.where(id: busy_ids)
end
```

`get_available_users` retorna um Hash com **todos os usuários da conta**, independente do
tamanho. O filtro por `'busy'` e o `map(&:to_i)` são feitos em Ruby. Para contas com
centenas de agentes, isso carrega e processa toda a estrutura Redis em memória a cada
chamada entrante.

### Correção pendente

Adicionar método `get_busy_users(account_id, user_ids:)` ao `OnlineStatusTracker` que
receba os IDs elegíveis e filtre direto no Redis (via `HMGET`):

```ruby
def busy_agents
  eligible_ids = recipients_base_scope.ids   # 1 query SQL
  return User.none if eligible_ids.empty?

  busy_ids = OnlineStatusTracker.get_busy_users(inbox.account_id, user_ids: eligible_ids)
  recipients_base_scope.where(id: busy_ids)
end
```

```ruby
# online_status_tracker.rb
def self.get_busy_users(account_id, user_ids:)
  return [] if user_ids.empty?
  key = "online_status_#{account_id}"
  statuses = redis.hmget(key, *user_ids.map(&:to_s))
  user_ids.zip(statuses)
           .select { |_, status| status == 'busy' }
           .map { |id, _| id.to_i }
end
```

Esta abordagem substitui o `hgetall` por `hmget` limitado ao conjunto elegível,
eliminando a carga de toda a hash do Redis.

---

## QC-08 · `ProcessWebhookJob` na fila `:low` atrasa eventos urgentes de chamada

**Categoria:** Performance / Confiabilidade  
**Arquivo:** `custom/app/jobs/wavoip/process_webhook_job.rb` (linha 3)

### Descrição

```ruby
queue_as :low
```

Eventos `INCOMING_RING` têm janela curta — o agente precisa ver a notificação antes que
a chamada seja atendida ou expire. Na fila `:low`, o job compete com trabalho em massa e
tarefas de manutenção.

`EscalateRingJob` vai para `:default`, mas depende do `ProcessWebhookJob` ter sido processado
antes — se o webhook de RING ainda está na fila `:low` quando a escalação dispara, a chamada
pode nem existir no banco ainda.

### Correção

Separar por tipo de evento:

```ruby
def perform(inbox_id, payload)
  # ...
end

def queue_for_payload(payload)
  case payload['type']
  when 'CALL' then :default   # urgente — toque, aceite, encerramento
  when 'RECORD' then :low     # não urgente — gravação pode chegar depois
  when 'DEVICE' then :low
  else :default
  end
end
```

Ou mais simples: subir todo o `ProcessWebhookJob` para `:default` e criar
`Wavoip::AttachRecordingJob` separado na fila `:low` para o processamento de RECORD (já existe).

---

## QC-10 · `mediaByInbox` acumula estado sem ser limpo no disconnect

**Categoria:** Memory leak  
**Arquivo:** `custom/app/javascript/dashboard/lib/wavoip/wavoipMedia.js`

### Descrição

`mediaByInbox` é um `Map` de módulo que armazena `ref`s de dispositivos de áudio por inbox.
Quando `disconnectWavoipInbox` é chamado, `clearWavoipDeviceStatus(inboxId)` é executado
(limpa o Map de device status), mas nenhum chamador limpa `mediaByInbox`:

```js
// wavoipMedia.js
const mediaByInbox = new Map();   // nunca removido

export const ensureMediaState = inboxId => {
  if (!mediaByInbox.has(inboxId)) {
    mediaByInbox.set(inboxId, { inputDevices: ref([]), outputDevices: ref([]), ... });
  }
  return mediaByInbox.get(inboxId);
};
```

Cada inbox que se conectar/desconectar durante a sessão do browser acumula 4 `ref`s no Map.
Em uso normal é pequeno, mas em sessões longas ou troca frequente de inboxes cresce
indefinidamente.

### Correção

Exportar `clearWavoipMediaForInbox` e chamá-lo dentro de `disconnectWavoipInbox`:

```js
// wavoipMedia.js
export function clearWavoipMediaForInbox(inboxId) {
  mediaByInbox.delete(inboxId);
}

// wavoipClientRegistry.js — dentro de disconnectWavoipInbox
import { clearWavoipMediaForInbox } from './wavoipMedia';
// ...
clearWavoipMediaForInbox(inboxId);
clients.delete(inboxId);
```

---

## QC-11 · `transition_allowed?` permite transições entre status terminais

**Categoria:** Lógica de estado  
**Arquivo:** `custom/app/services/wavoip/calls/call_status_applier.rb`

### Descrição

```ruby
def transition_allowed?(call, mapped_status)
  return true unless call.terminal?
  return false if mapped_status == 'ringing'
  return false if mapped_status == 'in_progress' && call.status != mapped_status
  true   # ← terminal → terminal é permitido
end
```

A guarda bloqueia `terminal → ringing` e `terminal → in_progress`, mas permite
`completed → no_answer` ou `no_answer → failed` se um webhook atrasado chegar. Isso
pode sobrescrever o status final de uma chamada encerrada:

- Chamada termina com `ENDED` → `completed`
- 5s depois chega `NOT_ANSWERED` (webhook atrasado do Wavoip) → `no_answer`
- Status histórico da chamada fica incorreto

O `build_update_attrs` tem guard `return nil if effective_status == call.status`, que bloqueia
a mesma transição terminal — mas não bloqueia cross-terminal (ex: `completed` → `no_answer`).

### Correção

Bloquear qualquer transição de terminal para um status terminal diferente:

```ruby
def transition_allowed?(call, mapped_status)
  return true unless call.terminal?
  return false if mapped_status == 'ringing'
  return false if mapped_status == 'in_progress'
  return false if status_mapper.terminal?(mapped_status) && mapped_status != call.status

  true
end
```

A exceção é o caso `HANDLED_REMOTELY` (que é um terminal legítimo mesmo sem `ringing`
anterior) — já tratado em `contextual_terminal_status` antes de chegar ao `transition_allowed?`.

---

## QC-12 · `webhook_url` silencia falha de configuração com `localhost:3000`

**Categoria:** Configuração  
**Arquivo:** `custom/app/models/channel/wavoip.rb`

### Descrição

```ruby
def webhook_url
  base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  "#{base}/webhooks/wavoip/#{webhook_key}"
end
```

Se `FRONTEND_URL` não estiver definido em produção, a URL exibida para o admin na
settings page será `http://localhost:3000/webhooks/wavoip/...`. O admin copia essa URL
e a configura no painel Wavoip — o webhook nunca chega, sem nenhum erro visível na
aplicação. É um silent failure de configuração.

### Correção

Usar a configuração centralizada do Chatwoot (se existir) ou falhar com mensagem clara:

```ruby
def webhook_url
  base = Rails.configuration.try(:frontend_url) ||
         ENV['FRONTEND_URL'] ||
         raise(ArgumentError, 'FRONTEND_URL must be configured for Wavoip webhooks')
  "#{base}/webhooks/wavoip/#{webhook_key}"
end
```

Ou mais conservador — retornar `nil` e exibir aviso na UI se `FRONTEND_URL` estiver vazio:

```ruby
def webhook_url
  base = ENV['FRONTEND_URL'].presence
  return nil if base.blank?
  "#{base}/webhooks/wavoip/#{webhook_key}"
end
```

`WavoipCallingPage.vue` já trata `webhookUrl` vazio com `<p v-else>... UNAVAILABLE</p>`.

---

## QC-13 · `onOutboundConnected` é código morto

**Categoria:** Código morto  
**Arquivo:** `custom/app/javascript/dashboard/lib/voice/voiceCallCableRegistry.js`

### Descrição

```js
onOutboundConnected() {},   // ← handler registrado mas sem implementação
```

O método está listado no objeto `wavoipVoiceCableHandlers` mas é um no-op. Duas
interpretações possíveis:

1. O backend nunca emite `voice_call.outbound_connected` — nesse caso o handler
   pode ser removido para evitar confusão
2. O backend emite e há uma implementação faltando — `voice_call.outbound_accepted`
   (`broadcast_accepted`) é o equivalente; se há `outbound_connected` distinto de
   `outbound_accepted`, o comportamento esperado nunca foi implementado

Verificar no `Broadcaster`: apenas `broadcast_accepted` existe (usado para `in_progress`
de chamadas de saída). `voice_call.outbound_connected` não é emitido em nenhum lugar.

### Correção

Remover o handler inativo:

```js
export const wavoipVoiceCableHandlers = {
  onIncoming(data) { /* ... */ },
  onOutboundAccepted(data) { /* ... */ },
  onAccepted(data) { /* ... */ },
  onEnded(data) { /* ... */ },
  // onOutboundConnected removido — evento não emitido pelo backend
};
```

Se no futuro for necessário um evento de "peer conectou mas chamada ainda não ativa",
implementar com lógica concreta.

---

## QC-14 · `test_wavoip_webhook` executa job de forma síncrona bloqueando thread Puma

**Categoria:** Performance / Confiabilidade  
**Arquivo:** `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb`

### Descrição

```ruby
def test_wavoip_webhook
  Wavoip::ProcessWebhookJob.perform_now(   # ← síncrono
    @inbox.id,
    { 'type' => 'DEVICE', 'status' => 'open', 'phone' => channel.phone_number }
  )
  @inbox.update_account_cache
  render json: { ok: true, webhook_verified: channel.reload.webhook_verified? }
end
```

`perform_now` bloqueia o thread Puma durante toda a execução do job (dispatcher →
`DeviceHandler` → `channel.update!`). Em produção com Puma multi-thread, isso consome
um thread de pool por até ~200ms para uma operação que o usuário usa raramente.

Adicionalmente, `ProcessWebhookJob` é na fila `:low` (ver QC-08), mas `perform_now`
ignora filas — executa sempre inline. Isso significa que o comportamento de test é
diferente do webhook real (que vai para fila).

### Correção

Usar `perform_later` e retornar imediatamente, deixando o frontend fazer polling do
`webhook_verified?` (já faz via `fetchInboxItem` após a resposta):

```ruby
def test_wavoip_webhook
  Wavoip::ProcessWebhookJob.perform_later(
    @inbox.id,
    { 'type' => 'DEVICE', 'status' => 'open', 'phone' => channel.phone_number }
  )
  render json: { ok: true, webhook_verified: channel.webhook_verified? }
end
```

O frontend já chama `fetchInboxItem` após receber a resposta — o status verificado
aparecerá quando o job processar (geralmente < 1s em ambiente não congestionado).

---

## QC-09 · `DeviceStatusService` faz dois `channel.reload` consecutivos

**Categoria:** Performance  
**Arquivo:** `custom/app/services/wavoip/device_status_service.rb`

### Descrição

`connection_payload` chama `persist_status!` (que faz `channel.update!`) e depois
`channel.reload`:
```ruby
def connection_payload(force: false)
  live = refresh_device_status!(force: force)   # → persist_status! → channel.update!
  channel.reload                                 # 1º reload
  config = channel.provider_config || {}
  # ...
end
```

`build_qr_payload` faz o mesmo:
```ruby
def build_qr_payload(info, token)
  channel.reload   # 2º reload em fluxos que passam por connection_payload + build_qr_payload
```

Além disso, `persist_status!` atualiza `phone_number` silenciosamente se o Wavoip retornar
um número diferente:
```ruby
channel.update!(phone_number: contact_phone) if contact_phone.present?
```

Sem log, sem validação. Se o Wavoip retornar um número incorreto (ex: bug na API), o
`phone_number` do canal é sobrescrito silenciosamente.

### Correção

1. Consolidar para um único `channel.reload` por fluxo.
2. Adicionar log e validação ao atualizar `phone_number`:

```ruby
if contact_phone.present? && contact_phone != channel.phone_number
  Rails.logger.info("[WAVOIP] Atualizando phone_number channel=#{channel.id} de=#{channel.phone_number} para=#{contact_phone}")
  channel.update!(phone_number: contact_phone)
end
```
