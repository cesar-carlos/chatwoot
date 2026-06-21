# Erros HTTP — Evolution Go API

Referência para `ApiClient#error_message` e logs operacionais. Baseado no schema `ErrorResponse` do OpenAPI oficial.

---

## Formato padrão de erro

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid or missing API key"
  },
  "meta": {
    "timestamp": "2024-01-15T10:30:00Z",
    "path": "/send/text",
    "method": "POST"
  }
}
```

**Helper Ruby sugerido:**

```ruby
def error_message(response)
  parsed = response.parsed_response
  parsed.dig('error', 'message') || parsed['message'] || response.body
end
```

---

## Códigos HTTP

| HTTP | Significado típico | Ação Chatwoot |
|------|-------------------|---------------|
| **400** | Body inválido | Validar params antes do send; mostrar erro no wizard |
| **401** | `apikey` ausente ou errada | Distinguir global vs instance token |
| **403** | Permissão insuficiente | Global key em endpoint de instância ou vice-versa |
| **404** | Instância/recurso não encontrado | Recriar instância ou corrigir `instance_id` |
| **500** | Erro interno Go | Retry com backoff; log `meta.path` |

---

## Códigos `error.code` (amostra OpenAPI)

| code | Contexto |
|------|----------|
| `BAD_REQUEST` | Campos obrigatórios faltando |
| `UNAUTHORIZED` | API key inválida |
| `FORBIDDEN` | Key correta mas sem permissão para operação |
| `NOT_FOUND` | Instância, mensagem ou destinatário |
| `INTERNAL_SERVER_ERROR` | Falha servidor |

---

## Erros por endpoint (mensagens documentadas)

### Instance

| Endpoint | 400 message (exemplo) |
|----------|----------------------|
| `POST /instance/create` | Invalid request data. Instance information is required. |
| `POST /instance/connect` | Invalid request data. Instance information is required. |
| `DELETE /instance/delete/{id}` | Invalid request data. Instance ID is required. |

### Send

| Endpoint | 400 message (exemplo) |
|----------|----------------------|
| `POST /send/text` | Invalid request data. Text and recipient information are required. |
| `POST /send/media` | Invalid request data. Media and recipient information are required. |

### Message

| Endpoint | 404 message (exemplo) |
|----------|----------------------|
| `POST /message/markread` | Message not found |
| `POST /message/status` | Message not found |
| `POST /message/react` | Message not found |

---

## Mapeamento UI

| Erro API | Mensagem usuário (en) |
|----------|----------------------|
| 401 create | Invalid global API key |
| 401 send | Invalid instance token — reconnect inbox |
| 404 connect | Instance not found — check name/token |
| 400 send text | Phone number and message text are required |

i18n: [frontend-wizard-spec.md § i18n](./frontend-wizard-spec.md)

---

## Webhook receiver (Chatwoot)

Evolution Go espera **200** rápido. Não retornar 401 após validar — logar e 200 para evitar retry storm (5× / 30s).

| Resposta CW | Efeito |
|-------------|--------|
| 200 | OK — sem retry |
| 4xx/5xx | Go retenta até 5 vezes |
