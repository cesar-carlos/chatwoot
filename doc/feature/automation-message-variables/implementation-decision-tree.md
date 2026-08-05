# Automation message variables — Árvore de decisão

```mermaid
flowchart TD
  Q[Expor variaveis na Automacao]
  A[Opcao A: Liquid + chips UX]
  B[Opcao B: Copiar gsub das workflow rules]
  C[Opcao C: So documentar menu existente]

  Q --> A
  Q --> B
  Q --> C

  A --> R[Recomendado]
  B --> X[Duplica motor]
  C --> X2[UX insuficiente]
```

## Opção A — Liquid existente + chips/prévia (RECOMENDADA)

**Ideia:** Não reinventar interpolação; o Message já processa Liquid em outgoing. Melhorar descoberta (chips) e fechar gaps (`phone`, `rule.name`).

| Prós | Contras |
|------|---------|
| Zero mudança no ActionService | Semântica `conversation.id` = display_id (histórico) |
| Reusa drops / custom attributes | Agent vazio se sem assignee |
| Alinha ReplyBox e Automação | — |

**Veredito:** ✅ escolhida.

## Opção B — Interpolator custom como workflow rules

Descartada: dois motores para a mesma sintaxe `{{}}`, risco de drift (`phone` vs `phone_number`, ids).

## Opção C — Só docs / i18n

Descartada: admin ainda não vê chips; bug `contact.phone` permanece.

## Decisões auxiliares

| Pergunta | Decisão |
|----------|---------|
| Novo interpolator? | Não |
| `rule` drop? | Sim via `Current.executed_by` |
| `conversation.id` interno? | Não no MVP |
