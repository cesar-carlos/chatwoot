# Análise de implementação — Evolution Go

Notas do levantamento jun/2026. **Sem código local** — baseado em documentação oficial, wiki GitHub e Postman.

---

## Stack técnica

| Componente | Tecnologia |
|------------|------------|
| Linguagem | Go 1.24+ |
| HTTP | Gin / net/http + ServeMux |
| WhatsApp | whatsmeow (fork Evolution Foundation) |
| DB | PostgreSQL (auth + users) — obrigatório |
| ORM | GORM |
| Filas | RabbitMQ, NATS (opcional) |
| Storage mídia | MinIO/S3 (opcional) |
| Docs runtime | Swagger em `/swagger/index.html` |
| Container | `evoapicloud/evolution-go` |

---

## Modelo de autenticação

```
┌─────────────────────────────────────────┐
│ GLOBAL_API_KEY (.env)                   │
│ → create/delete/list instances          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ Instance Token (UUID por instância)     │
│ → connect, qr, status, send messages    │
└─────────────────────────────────────────┘
```

Diferente da Evolution API onde `hash` do create serve como apikey da instância.

---

## Fluxo webhook

```
WhatsApp → whatsmeow → Event Router → HTTP POST webhookUrl
                                      (configurado no connect)
```

- Sem `POST /webhook/set` separado
- Retry: 5 tentativas, 30s intervalo
- Eventos em UPPERCASE curto: `MESSAGE`, não `MESSAGES_UPSERT`

---

## Payload mensagem (whatsmeow)

Estrutura `data` compatível com normalizer Baileys da Evolution API (~80%):

- `key.remoteJid`, `key.id`, `key.fromMe`
- `message.conversation` / `imageMessage` / etc.
- `pushName`, `messageTimestamp`

Permite copiar lógica de extração de phone e `source_id` com ajuste de nomes de evento.

---

## Licenciamento

Evolution Go exige ativação de licença no primeiro acesso (Magic Link / Google / GitHub). **Fora do escopo** do adapter Chatwoot — pré-requisito de infra do operador.

---

## Gaps do levantamento (resolver no spike)

| # | Gap | Ação |
|---|-----|------|
| 1 | Path send text | ✅ `POST /send/text` confirmado OpenAPI |
| 2 | `data.Info.ID` no send response | Fixture `send_text_response.json` no spike |
| 3 | Payload `READ_RECEIPT` | Fixture Fase 2 |
| 4 | Headers custom no webhook connect | Testar se suportado |
| 5 | Versão Docker estável | Congelar em target-version.txt |
| 6 | `advanced-settings` schema completo | Swagger export |

---

## Comparação esforço vs Evolution API

| Área | Evolution API | Evolution Go |
|------|---------------|--------------|
| ApiClient | Médio — paths `:instanceName` | Médio — dual auth + unwrap |
| ConnectionService | `set_webhook` + connect GET | connect POST com webhook inline |
| Normalizer | `MESSAGES_UPSERT` | `MESSAGE` — lógica similar |
| Wizard UI | Similar | Similar + campo global_api_key |
| Ops | Sem licença (self-host) | Licença + PostgreSQL obrigatório |

**Estimativa relativa:** ~90% do esforço Evolution API Fase 1, com spike adicional de paths.

---

## Código Chatwoot existente

| Arquivo | Relação |
|---------|---------|
| `custom/.../evolution/api_client.rb` | **Não reusar** — Evolution API Node |
| Fase 0 registry/prepends | **Reusar** quando implementado |

---

## Próximos passos

1. Subir Evolution Go via Docker + ativar licença
2. Executar [validation-checklist.md](./validation-checklist.md)
3. Importar Postman collection e marcar [postman-validation.md](./postman-validation.md)
4. Implementar Fase 0 (se pendente) → Fase 1 Evolution Go
