# Attachment Download State — Improvements backlog

Pós-MVP e itens já aplicados na rodada de UX (16/jul/2026).

---

## Já entregue (MVP + UX)

- Estado local com contagem por attachment
- Chip + bubble + sidebar Shared files
- Download unificado via `downloadFile` FORK
- Isolamento account + user
- Docs nesta pasta
- Tooltip com `DOWNLOAD_AGAIN`
- Bubble alinhado (teal + badge + secondary Mark/Clear)
- Badge de contagem visível sem hover
- Sidebar: filtro All / Pending / Downloaded + progresso `N of M`
- Mark as done / Clear mark (right-click no chip/sidebar; botão no bubble)
- Microanimação de sucesso (`isJustMarked`)
- Extensão a Image / Audio / GalleryView / Shared Media
- Indicador na preview da lista de conversas
- Prune LRU (máx. 500 entradas)

---

## P1 — Restante

| ID | Item | Notas |
|----|------|-------|
| AD-P1-3 | Spec Vitest do composable | `markDownloaded`, scope key, contagem, clear |

---

## P2 — Produto / UX maior

| ID | Item | Notas |
|----|------|-------|
| AD-P2-2 | Ação “Clear download history” no profile | Limpa só o scope do user atual |
| AD-P2-4 | Sync multi-device via API | Só se produto exigir |

---

## P3 — Exploratório

| ID | Item | Notas |
|----|------|-------|
| AD-P3-1 | Heurística “printed” via `beforeprint` | Pouco confiável |
| AD-P3-2 | Atalho teclado global “mark as handled” | Além do right-click |

---

## Não fazer

- Backend só para preferência estética de UI (sem demanda multi-device)
- Estados “lido” / “copiado” separados sem pedido claro
- Editar `routes.rb` / Gemfile por este feature
