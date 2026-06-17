# Estimativa de esforço e fases

Cronograma sugerido para implementar provider gateway não oficial no fork.

---

## Fases

| Fase | Escopo | Esforço |
|------|--------|---------|
| **1 — MVP mensagens** | Provider envio texto, normalizer webhook texto, inbox setup, status básico | 2–3 semanas |
| **2 — Mídia + templates** | Upload/download mídia, sync templates (se gateway suportar) ou bypass, reply | 2–4 semanas |
| **3 — Interativos + operação** | Botões/listas, health conexão, reconexão QR, logs/alertas | 2–3 semanas |
| **4 — Chamadas** | **Não recomendado** para não oficial; ver [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md) | N/A ou projeto separado |

---

## Dependências críticas

1. Escolher **um** gateway piloto (ex.: Evolution API v2) e congelar contrato webhook antes de codar
2. Definir mapeamento de identificadores (`@s.whatsapp.net` → `ContactInbox#source_id`)
3. Validar suporte a mídia e interativos no gateway escolhido antes da Fase 2

---

## Riscos que impactam cronograma

| Risco | Impacto |
|-------|---------|
| Mudança de formato webhook entre versões do gateway | Retrabalho no normalizer |
| Banimento de número em testes | Atraso + necessidade de números descartáveis |
| Gateway sem templates oficiais | Bypass manual ou desabilitar janela 24h no Chatwoot (não recomendado) |
| Tentativa de paridade com cloud (campanhas, CSAT) | +4–8 semanas sem ganho proporcional |

---

## Equipe mínima sugerida

- 1 dev backend (Ruby: provider, normalizer, job)
- 1 dev frontend (Vue: wizard setup, status conexão)
- Gateway piloto rodando em ambiente de dev/staging

---

## Critérios de done por fase

### Fase 1
- [ ] Criar inbox gateway com URL + token
- [ ] Receber mensagem texto inbound → conversa no dashboard
- [ ] Enviar resposta texto outbound
- [ ] Status `sent`/`delivered` mapeados (se gateway enviar)

### Fase 2
- [ ] Enviar/receber imagem e documento
- [ ] Templates listados ou bypass documentado
- [ ] Reply/quote se gateway suportar

### Fase 3
- [ ] Botões/listas outbound
- [ ] Alerta de desconexão + fluxo QR
- [ ] Health check no settings da inbox

### Fase 4
- [ ] Avaliar viabilidade com gateway específico antes de iniciar
- [ ] Se viável: projeto separado com escopo próprio
