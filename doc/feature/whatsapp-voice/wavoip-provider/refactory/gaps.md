# Gaps de comportamento — Wavoip

Features implementadas com cobertura incompleta. O fluxo feliz funciona, mas casos
esperados em produção não são tratados corretamente.

---

## GAP-01 · `offline_fallback: 'none'` não bloqueia a escalação por timeout

> **Status (26 jun. 2026):** Corrigido — `escalated_users` retorna `User.none` quando
> `incoming_call_offline_fallback == 'none'` (`incoming_call_recipients.rb`).

**Severidade:** Alta (histórico)  
**Arquivos:**
- `custom/app/services/wavoip/calls/incoming_call_recipients.rb`
- `custom/app/services/wavoip/calls/broadcaster.rb`

### Descrição

A opção "Quando nenhum agente estiver online → Nenhum" impede notificações no toque inicial
— `users` retorna `User.none`, `pubsub_tokens` retorna `[]`, o ActionCable broadcast não chega
a ninguém. Até aqui correto.

Mas `escalated_users` ignora completamente `incoming_call_offline_fallback`:

```ruby
# incoming_call_recipients.rb
def escalated_users
  broad_fallback_scope   # sempre inbox members + admins (se ativado)
end
```

Com `offline_fallback: 'none'` + `ring_timeout_seconds: 60` o comportamento real é:
- Toque 0–60s: ✅ nenhum agente notificado
- Após 60s: ❌ todos os inbox members + admins são notificados via ActionCable e push

Isso contradiz diretamente a intenção do admin que configurou `none`.

### Correção

`escalated_users` deve respeitar o fallback configurado. A escalação deve usar o mesmo
resolver da regra offline, não sempre `broad_fallback_scope`:

```ruby
def escalated_users
  return User.none if offline_fallback == 'none'

  # fallback mais amplo dentro da política configurada
  resolver = OFFLINE_FALLBACK_RESOLVERS.fetch(offline_fallback, :assignee_with_broad_fallback)
  # escalação sobe para broad_fallback dentro da política, não ignora
  broad_fallback_scope
end
```

Alternativa mais limpa: tornar `escalated_users` ciente de que só expande o escopo do
fallback já configurado, nunca o ignora:

```ruby
def escalated_users
  return User.none if offline_fallback == 'none'
  broad_fallback_scope
end
```

---

## GAP-02 · `accepted_by_agent_id` pode não ser persistido sem erro visível

**Severidade:** Alta  
**Arquivo:** `custom/app/javascript/dashboard/lib/wavoip/wavoipAcceptRecorder.js`

### Descrição

Quando `recordAcceptedBy` não encontra o `callId` no store (a chamada ainda não foi
mapeada para um `dbCallId`), ela enfileira o callSid em `pendingAcceptByCallSid`.
`flushAcceptedByRecording` é chamado em dois pontos: após `acceptIncomingCall` e no
handler `onIncoming` do cable.

Se a chamada à API falhar em `flushAcceptedByRecording`, o item é re-enfileirado:
```js
try {
  await CallsAPI.recordAccept(dbCallId);
} catch (_) {
  pendingAcceptByCallSid.add(callSid);   // re-enfileirado, mas sem novo flush agendado
}
```

Após a re-enfileiração, `flush` só é invocado novamente se outro `onIncoming` cable event
chegar para o mesmo callSid — o que jamais acontece pois `onIncoming` dispara uma vez por
chamada. O `PATCH /calls/:id` nunca é enviado. O campo `accepted_by_agent_id` fica `null`
em produção sem nenhum log ou alerta.

### Correção

Opção A — retry com backoff exponencial limitado:
```js
async function attemptRecordAccept(dbCallId, attempt = 1) {
  try {
    await CallsAPI.recordAccept(dbCallId);
  } catch (_) {
    if (attempt < 3) {
      setTimeout(() => attemptRecordAccept(dbCallId, attempt + 1), 1000 * attempt);
    }
    // após 3 tentativas: logar aviso (não silencioso)
  }
}
```

Opção B — mover a responsabilidade para o backend: o `CallStatusApplier` já tem
`call.accepted_by_agent_id`; ao receber `ACTIVE` para chamada inbound, registrar o agente
que estava "joining" (via Redis) em vez de depender do `PATCH` do browser.

---

## GAP-03 · Token rotacionado não reconecta o SDK

**Severidade:** Média  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipConnection.js`

### Descrição

Após um admin rotacionar o webhook key via `regenerate_wavoip_webhook_key`, o token do
dispositivo continua o mesmo — mas se o `device_token` for rotacionado (ex: reconfiguração
de inbox), o frontend não percebe porque `connectInbox` faz early return quando o inbox
já está em `connectedInboxIds`:

```js
const connectInbox = async inboxId => {
  if (connectedInboxIds.has(inboxId)) {
    return getWavoipClient(inboxId);   // ← nunca verifica se o token mudou
  }
  // ...
};
```

`connectWavoipInbox` no registry trata corretamente a troca de token:
```js
if (existing?.token === deviceToken) return existing.client;
if (existing) await disconnectWavoipInbox(inboxId);
```
— mas nunca é alcançado.

### Correção

`syncConnections` (chamado a cada mudança de `wavoipSdkSyncKey`) deve forçar reconexão
quando o token mudou, mesmo com o inbox já em `connectedInboxIds`. A forma mais simples é
remover o inbox de `connectedInboxIds` se o token armazenado divergir do token recém-buscado:

```js
const connectInbox = async inboxId => {
  if (connectedInboxIds.has(inboxId)) {
    const existingEntry = getWavoipClientEntry(inboxId);
    const { data } = await InboxesAPI.getWavoipSdkBootstrap(inboxId);
    const freshToken = data?.device_token;
    if (freshToken && existingEntry?.token === freshToken) {
      return existingEntry.client;   // token igual → reutiliza
    }
    connectedInboxIds.delete(inboxId);  // token mudou → reconecta
  }
  // ... restante do fluxo existente
};
```

Ou de forma mais eficiente: incluir o `device_token` (ou um hash dele) no `wavoipSdkSyncKey`
para que qualquer mudança de token force `syncConnections` a desconectar e reconectar.

---

## GAP-04 · `PhoneNormalizer` assume Brasil para qualquer inbox com prefixo 55

**Severidade:** Média  
**Arquivo:** `custom/app/services/wavoip/phone_normalizer.rb`

### Descrição

Qualquer número de 10–11 dígitos sem `+` prefixo que chegar a um inbox cujo telefone começa
com `55` recebe o prefixo `+55`:

```ruby
def self.normalize(phone, inbox_phone: nil)
  return "+55#{digits}" if brazilian_inbox?(inbox_phone) && digits.match?(/\A\d{10,11}\z/)
  "+#{digits}"
end

def self.brazilian_inbox?(inbox_phone)
  inbox_phone.to_s.gsub(/\D/, '').start_with?('55')
end
```

Um número americano de 10 dígitos (`2125551234`) chegando por um inbox brasileiro seria
normalizado para `+552125551234`. Igualmente, qualquer número sem `+` de outro país LATAM
roteado por inbox brasileiro seria incorretamente prefixado.

Isso afeta `contact_phone_for` em `ConversationLinker`, que determina com qual contato a
chamada é associada — resultando em contatos duplicados com número errado.

### Correção

Usar `phonelib` (já dependência do Chatwoot) para parseamento E.164 com fallback
country-hint derivado do prefixo do inbox:

```ruby
def self.normalize(phone, inbox_phone: nil)
  return if phone.blank?
  raw = phone.to_s.strip
  return raw if raw.start_with?('+')

  # Tenta parsear com country hint derivado do inbox
  country = country_hint(inbox_phone)
  parsed = Phonelib.parse(phone, country)
  return "+#{parsed.e164.delete('+')}" if parsed.valid?

  # Fallback: prefixo direto
  "+#{phone.to_s.gsub(/\D/, '')}"
end

def self.country_hint(inbox_phone)
  Phonelib.parse(inbox_phone)&.country
end
```

---

## GAP-05 · `ring_timeout_seconds` sem limite máximo no backend

**Severidade:** Baixa  
**Arquivos:**
- `custom/app/models/channel/wavoip.rb`
- `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb`

### Descrição

`ring_timeout_seconds` não tem validação de upper bound. Um valor enviado diretamente via
API (`ring_timeout_seconds: 86400`) agenda um `EscalateRingJob` para 24h no futuro.
O job verifica `call.ringing?` antes de executar, então não causa dado — mas polui
a fila do Sidekiq com jobs stale.

O frontend restringe a `[0, 30, 60, 90, 120]`, mas a API aceita qualquer inteiro.

### Correção

Validação no model:

```ruby
# channel/wavoip.rb
validates :ring_timeout_seconds_value, numericality: {
  greater_than_or_equal_to: 0,
  less_than_or_equal_to: 300,
  allow_nil: true
}

def ring_timeout_seconds_value
  provider_config['ring_timeout_seconds']&.to_i
end
```

Ou no controller `create_wavoip_channel`:
```ruby
ring_timeout = wavoip_params.dig(:provider_config, :ring_timeout_seconds).to_i
raise ActionController::BadRequest if ring_timeout > 300
```

---

## GAP-06 · Listener de device vaza se `device.on()` não retornar função de unsubscribe

**Severidade:** Baixa  
**Arquivo:** `custom/app/javascript/dashboard/composables/wavoip/useWavoipConnection.js`

### Descrição

`waitForDeviceOpen` assume que `device.on(...)` retorna uma função de cleanup:

```js
unsubscribe = device.on?.('statusChanged', status => {
  if (status === 'open') finish(true);
});
// ...
unsubscribe?.();  // no-op se device.on() retornar undefined
```

Se o SDK (versão atual ou futura) não retornar uma função de unsubscribe, o listener
`statusChanged` jamais é removido. Cada chamada a `waitForDeviceOpen` (que ocorre em
`ensureDeviceReadiness` em toda conexão) adiciona um novo listener — o device acumula
múltiplos listeners.

### Correção

Guardar o handler e usar `device.off` como fallback:

```js
const handler = status => {
  if (status === 'open') finish(true);
};
const unsubscribeFn = device.on?.('statusChanged', handler);

const cleanup = () => {
  if (typeof unsubscribeFn === 'function') {
    unsubscribeFn();
  } else {
    device.off?.('statusChanged', handler);
  }
};
```

---

## GAP-07 · `assignee` e `assignee_or_inbox_members` mapeiam para o mesmo resolver

**Severidade:** Baixa  
**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

### Descrição

```ruby
OFFLINE_FALLBACK_RESOLVERS = {
  'none'                                         => :none_scope,
  'assignee'                                     => :assignee_with_inbox_fallback,   # ← mesmo
  'assignee_or_team_members'                     => :assignee_with_team_fallback,
  'assignee_or_inbox_members'                    => :assignee_with_inbox_fallback,   # ← mesmo
  'assignee_or_inbox_members_and_administrators' => :assignee_with_broad_fallback
}.freeze
```

`assignee_with_inbox_fallback` faz:
```ruby
def assignee_with_inbox_fallback
  assignee_or_fallback(inbox_member_scope)
end
```

Se não há assignee, **ambas** as opções notificam todos os inbox members. A opção
`assignee` deveria notificar apenas o assignee (ou ninguém), sem escalar para inbox members.

### Correção

Adicionar resolver específico para `assignee`:

```ruby
OFFLINE_FALLBACK_RESOLVERS = {
  'none'                                         => :none_scope,
  'assignee'                                     => :assignee_only_scope,            # ← novo
  'assignee_or_team_members'                     => :assignee_with_team_fallback,
  'assignee_or_inbox_members'                    => :assignee_with_inbox_fallback,
  'assignee_or_inbox_members_and_administrators' => :assignee_with_broad_fallback
}.freeze

def assignee_only_scope
  assignee_scope   # User.none se não houver assignee
end
```

---

## GAP-08 · `incoming_call_notify_busy_agents` não se aplica à escalação

> **Status: ✅ Implementado** — `escalated_users` já verifica `incoming_call_notify_busy_agents?`
> antes de `broad_fallback_scope`. Spec de cobertura em
> `spec/custom/services/wavoip/calls/incoming_call_recipients_spec.rb`.

**Severidade:** Baixa  
**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

### Descrição (original)

A opção "Notificar agentes ocupados" deveria ser verificada também na escalação. O código
implementado respeita essa preferência:

```ruby
def escalated_users
  return User.none if offline_fallback == 'none'

  if channel.incoming_call_notify_busy_agents?
    busy = busy_agents
    return busy if busy.exists?
  end

  broad_fallback_scope
end
```

---

## GAP-ADMIN · Administradores online não recebiam o toque inicial

> **Status: ✅ Corrigido** — `recipients_base_scope` introduzido em 26 jun. 2026.
> Specs em `spec/custom/services/wavoip/calls/incoming_call_recipients_spec.rb`.

**Severidade:** Alta (comportamento divergia da intenção da configuração)  
**Arquivo:** `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

### Descrição

Quando `incoming_call_include_administrators = true`, os administradores eram incluídos
apenas em `broad_fallback_scope` (fallback offline / escalação) — nunca na prioridade 1
(online) nem na prioridade 2 (busy). Um administrador conectado e disponível não recebia
a notificação de chamada entrante, contradizendo diretamente a intenção da configuração.

A raiz do problema era que `online_member_users` e `busy_agents` usavam `inbox_member_scope`
(`User.where(id: inbox.member_ids)`) como escopo base, que exclui administradores que não
são membros explícitos da inbox.

### Correção

Introduzido `recipients_base_scope` como ponto único de verdade para o conjunto de
destinatários elegíveis. Todos os métodos de prioridade passam a usar este escopo:

```ruby
# Scope unificado: membros da inbox + admins (quando configurado)
def recipients_base_scope
  user_ids = inbox.member_ids.dup
  user_ids |= channel.account.administrators.ids if channel.incoming_call_include_administrators?
  User.where(id: user_ids)
end

def online_member_users   # prioridade 1: online
  online_ids = OnlineStatusTracker.get_available_users(inbox.account_id)
                                  .select { |_key, value| value == 'online' }
                                  .keys.map(&:to_i)
  recipients_base_scope.where(id: online_ids)
end

def busy_agents           # prioridade 2: busy (quando notify_busy_agents=true)
  busy_ids = OnlineStatusTracker.get_available_users(inbox.account_id)
                                .select { |_key, value| value == 'busy' }
                                .keys.map(&:to_i)
  recipients_base_scope.where(id: busy_ids)
end

def broad_fallback_scope  # prioridade 3: todos elegíveis (fallback offline)
  recipients_base_scope
end
```

**Efeito colateral no QC-07:** a introdução de `recipients_base_scope` removeu o
pré-filtro `.slice(*member_id_strings)` que havia sido aplicado em QC-07. Ver nota em
`code-quality.md#qc-07`.

---

## GAP-09 · `administratorsToggleDisabled` sem contrato no backend

**Severidade:** Baixa  
**Arquivos:**
- `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/WavoipCallingPage.vue`
- `custom/app/models/channel/wavoip.rb`
- `custom/app/services/wavoip/calls/incoming_call_recipients.rb`

### Descrição

Quando `offline_fallback === 'none'`, o toggle "Incluir administradores" é desabilitado
visualmente no frontend (`administratorsToggleDisabled: true`). Porém o backend não
valida essa restrição — é possível ter `incoming_call_include_administrators: true` com
`offline_fallback: 'none'` persistidos simultaneamente via API direta.

O estado inconsistente não causa erro imediato porque com `offline_fallback: 'none'` o
método `offline_recipients` retorna `User.none` (ignorando admins) — mas `escalated_users`
consulta `broad_fallback_scope` que respeita `incoming_call_include_administrators?`.
Ou seja: a combinação `none` + `include_admins: true` com timeout de escalação ainda
notifica admins via escalação.

Esse problema é parcialmente coberto por GAP-01 (escalação ignora `none`), mas o estado
inconsistente de configuração persiste independentemente.

### Correção

Opção A — validação no model:
```ruby
# channel/wavoip.rb
validate :administrators_toggle_consistent_with_offline_fallback

def administrators_toggle_consistent_with_offline_fallback
  return unless provider_config['incoming_call_offline_fallback'] == 'none'
  return unless provider_config['incoming_call_include_administrators'] == true

  errors.add(:provider_config, 'incluir administradores não é aplicável quando offline_fallback é none')
end
```

Opção B (mais simples) — o frontend, ao salvar `offline_fallback: 'none'`,
força `incoming_call_include_administrators: false` no payload de `saveCallRouting`:

```js
async handleOfflineFallbackChange(newValue) {
  const includeAdmins = newValue === 'none' ? false : this.includeAdministrators;
  await this.saveCallRouting({
    incoming_call_include_administrators: includeAdmins,
    incoming_call_offline_fallback: newValue,
    // ...
  });
}
```

---

## GAP-10 · `saveCallRouting` tem race condition de last-write-wins

**Severidade:** Baixa  
**Arquivo:** `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/WavoipCallingPage.vue`

### Descrição

Cada toggle/dropdown de roteamento envia **os 4 valores juntos** via `saveCallRouting`:

```js
await this.saveCallRouting({
  incoming_call_include_administrators: this.includeAdministrators,
  incoming_call_offline_fallback: this.offlineFallback,
  incoming_call_notify_busy_agents: this.notifyBusyAgents,
  ring_timeout_seconds: this.ringTimeoutSeconds,
});
```

Se dois admins estiverem na settings page simultaneamente:
1. Admin A muda `offline_fallback` → salva os 4 valores com seu estado local
2. Admin B muda `notify_busy_agents` 200ms depois → salva os 4 valores com **o estado local do B**
   — que não tem a mudança do Admin A (não fez fetch entre os dois saves)

O save do Admin B sobrescreve silenciosamente o `offline_fallback` configurado pelo Admin A.

### Correção

Opção A — fetch do estado atual do servidor antes de cada save (mais seguro):
```js
async saveCallRouting(updates) {
  await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
  const serverConfig = this.inbox.provider_config || {};
  await this.$store.dispatch('inboxes/updateInbox', {
    id: this.inbox.id,
    channel: {
      provider_config: { ...serverConfig, ...updates },
    },
  });
}
```

Opção B — salvar apenas o campo alterado (requer suporte a PATCH parcial de `provider_config`
no backend, que atualmente faz merge completo via `updateInbox`).

---

## GAP-11 · `WavoipDevicePanel` faz polling mesmo com device já conectado na montagem

**Severidade:** Baixa  
**Arquivo:** `custom/app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/WavoipDevicePanel.vue`

### Descrição

```js
onMounted(() => {
  refreshConnection({ forceLiveCheck: true });
  startPolling();   // ← começa sem checar isConnected.value
});
```

O watcher `watch(isConnected, connected => { if (connected) stopPolling(); })` só para o
polling quando o valor **muda** de false → true. Se a página abrir com `device_status: 'open'`
já na prop, o watcher não dispara (valor não mudou) e o polling de 5s continua para sempre,
fazendo requisições desnecessárias a `/wavoip_device_status` indefinidamente.

### Correção

```js
onMounted(() => {
  refreshConnection({ forceLiveCheck: true }).then(() => {
    if (!isConnected.value) startPolling();   // só poleia quando desconectado
  });
});
```

O watcher existente já cuida do caso em que a conexão cai depois de montado.
