# Viabilidade — canal WhatsApp com API não oficial

Matriz de paridade, desafios técnicos e nota de compliance para gateways como Evolution API, Baileys, WPPConnect, etc.

---

## Matriz de paridade

| Feature | whatsapp_cloud | default/360dialog | API não oficial (novo) |
|---------|:--------------:|:-----------------:|:----------------------:|
| Mensagens texto | ✅ | ✅ | ✅ (MVP) |
| Mídia entrada/saída | ✅ | ✅ | ⚠️ formato/criptografia varia |
| Templates Meta | ✅ sync WABA | ✅ sync BSP | ⚠️ muitos gateways **não** têm templates oficiais |
| Interativos (botões/listas) | ✅ | ✅ | ⚠️ depende do gateway |
| Grupos | ❌ (Cloud: individual only) | ❌ | ⚠️ alguns gateways sim — Chatwoot não modela |
| Status sent/delivered/read | ✅ | ✅ | ⚠️ mapear eventos |
| Read receipts | ✅ | ✅ | ⚠️ |
| Reply/quote | ✅ | parcial | ⚠️ |
| Reações | ignoradas | ignoradas | possível mas não implementado |
| Janela 24h + template forçado | ✅ | ✅ | ✅ (regra Chatwoot) |
| Campanhas one-off | ✅ cloud only | ❌ | ❌ inicialmente |
| CSAT auto-template | ✅ | ❌ | ❌ |
| Embedded signup | ✅ | ❌ | ❌ — QR/sessão manual |
| Health/reauth Meta | ✅ | parcial | ❌ — health próprio do gateway |
| Chamadas in-app WhatsApp | ✅ Enterprise | ❌ | ❌ na prática |
| Risco banimento | baixo (oficial) | baixo | **alto** |

---

## Desafios técnicos

1. **Sessão:** QR, reconexão, multi-device — estado no gateway, não no Chatwoot
2. **Webhook:** Evolution usa `event` + payload próprio; não é `entry/changes/value`
3. **Identificadores:** `@s.whatsapp.net`, LID/BSUID — mapear para `ContactInbox#source_id`
4. **Templates:** sem WABA → workaround (texto livre fora da janela = violação de política Meta)
5. **Mídia:** alguns gateways enviam base64 ou URL temporária criptografada
6. **Sem embedded signup:** wizard novo (URL + API key + status conexão + QR polling)

---

## Compliance (não é aconselhamento jurídico)

Uso de APIs não oficiais viola os Termos de Serviço do WhatsApp/Meta; risco de banimento do número e responsabilidade do operador. BSPs oficiais (Cloud, 360dialog, Twilio) são o caminho suportado comercialmente.

Para detalhamento de restrições evitadas vs novas, ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md).

---

## Veredito

| Escopo | Viável? |
|--------|---------|
| Mensagens texto (MVP) | ✅ Sim, com adaptador |
| Mídia + interativos | ⚠️ Depende do gateway piloto |
| Paridade cloud (campanhas, CSAT, echoes) | ❌ Não esperar |
| Chamadas nativas WhatsApp | ❌ Ver [generic-whatsapp-call-channel.md](./generic-whatsapp-call-channel.md) |

**Dependência crítica:** escolher **um** gateway piloto (ex.: Evolution API v2) e congelar contrato webhook antes de codar.
