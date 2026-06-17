# Twilio vs API não oficial vs Meta Cloud

Clarificação das três abordagens para WhatsApp no Chatwoot: o que se perde e o que se ganha em cada uma.

---

## Tabela comparativa

| | Meta Cloud (`whatsapp_cloud`) | 360dialog (`default`) | Twilio WhatsApp | API não oficial |
|--|:---:|:---:|:---:|:---:|
| Oficial Meta | ✅ | ✅ (BSP) | ✅ | ❌ |
| Setup | Embedded / manual keys | API key | Twilio console | QR + self-host |
| Templates WABA | ✅ | ✅ | ✅ | ❌/hack |
| Campanhas Chatwoot | ✅ | ❌ | ❌ | ❌ |
| Chamada **dentro** do WhatsApp | ✅ EE | ❌ | ❌ | ❌ |
| Chamada telefone (PSTN) | ❌ | ❌ | ✅ canal Voice | ❌ |
| Custo previsível | médio | médio | alto | infra própria |
| Risco ban | baixo | baixo | baixo | **alto** |

---

## O que se perde com API não oficial vs Cloud

- Embedded signup
- Health/reauth Meta
- Campanhas one-off
- CSAT template API
- Echoes coexistence (SMB)
- Chamadas nativas WhatsApp (Enterprise)
- Suporte comercial Meta

---

## O que se ganha com API não oficial

- Sem custo BSP por mensagem (só infra)
- Controle total do gateway
- Às vezes grupos/status extras (não usados pelo Chatwoot hoje)

---

## Twilio ≠ não oficial

**Twilio WhatsApp messaging** usa a **API oficial** via BSP; é outro canal (`Channel::TwilioSms` + `medium: whatsapp`), não Evolution/Baileys.

**Twilio Voice** é PSTN/conferência — **não** substitui chamadas nativas WhatsApp in-app. Ver [twilio-vs-whatsapp-native.md](../whatsapp-voice/twilio-vs-whatsapp-native.md).

---

## Quando escolher cada abordagem

| Cenário | Recomendação |
|---------|--------------|
| Produção comercial, compliance, chamadas | Meta Cloud (`whatsapp_cloud`) |
| BSP alternativo oficial, sem embedded signup | 360dialog (`default`) |
| Voz PSTN para números de telefone | Twilio Voice (`Channel::TwilioSms`) |
| Custo zero BSP, aceita risco ToS, mensagens only | Gateway não oficial (fork) |
