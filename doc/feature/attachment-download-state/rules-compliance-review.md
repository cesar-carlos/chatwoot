# Attachment Download State — Revisão de conformidade

Revisão pós-implementação contra as rules do fork e o plano MVP.

**Data:** 16/jul/2026

---

## Veredito geral

| Área | Status | Nota |
|------|--------|------|
| MVP / happy path (`chatwoot-core`) | ✅ | Só arquivos; sem backend |
| Fork workflow | ✅ | Lógica em `custom/`; FORK fino nos Vue |
| Architecture (lógica fora do component) | ✅ | Composable único; UI finas |
| Vue frontend (Tailwind / i18n) | ✅ | Tailwind tokens; EN only |
| Anti god class | ✅ | Storage centralizado; 3 superfícies consomem API pequena |
| Specs | ✅ omitidos | Regra: não escrever specs sem pedido |

---

## 1. `fork-workflow.mdc`

| Regra | Como atendemos |
|-------|----------------|
| Preferir `custom/` | `useAttachmentDownloadState.js` |
| Thin FORK em upstream | Imports + key + `action.disabled` |
| Não duplicar classes OSS | Reusa chip/bubble/sidebar |
| Commit scope | `feat(fork): …` quando versionar |

---

## 2. `architecture.mdc`

| Camada | Papel neste feature |
|--------|---------------------|
| Application (frontend) | Composable = uma responsabilidade (estado de download local) |
| Transport / UI | Chip, bubble, sidebar só disparam download e leem estado |
| Infrastructure | `downloadFile` / Active Storage (já existente) |

Sem HTTP params no storage; sem regras de negócio no controller.

---

## 3. `chatwoot-core.mdc` / `vue-frontend.mdc`

- Composition API + `<script setup>`
- Sem CSS scoped novo
- i18n EN em `conversation.json`
- Sem docs soltas fora de `doc/feature/` (esta pasta)
- Comentários FORK em inglês

---

## 4. Ajustes feitos na revisão pós-MVP

| Item | Ação |
|------|------|
| N `watch` por chip (lifecycle) | Substituído por `store.watch` único + `ensureLoaded` |
| Ordem `v-tooltip` no chip | Ajustada |
| Bubble sem disable no loading | `action.disabled` em `BaseAttachment` + wire no `File.vue` bubble |

---

## 5. Riscos aceitos no MVP

| Risco | Mitigação / aceite |
|-------|---------------------|
| localStorage cheio | Contagem por id é pequena; aceito |
| ID órfão após purge de anexo | Entrada local fica inerte; sem cleanup |
| Usuário limpa dados do site | Estado some (esperado) |
| `DOWNLOAD_AGAIN` unused | Key reservada para tooltip futuro |

---

## Checklist de merge

- [x] Composable em `custom/`
- [x] Marcadores `// FORK:` nos toques upstream
- [x] Só locale `en`
- [x] Sem migration / API
- [x] Docs em `doc/feature/attachment-download-state/`
