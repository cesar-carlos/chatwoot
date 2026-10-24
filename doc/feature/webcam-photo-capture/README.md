# Webcam Photo Capture

Captura de foto pela webcam no ReplyBox. A imagem entra como attachment normal da conversa (`File` JPEG → `onFileUpload`).

**Estado:** implementado (MVP) · revisão doc × código em 24/out/2026

| Área | Status |
|------|--------|
| Upload / envio de imagem | Reusa `onFileUpload` → `attachFile` |
| Preview de anexos | `AttachmentPreview` (sem bolha nova) |
| Detecção de webcam | `useWebcamAvailability` |
| Captura + dialog | `WebcamCapture/` |
| Botão na toolbar | `ReplyBottomPanel` (`i-ph-camera`), depois do share contact |
| Backend / feature flag | Nenhum |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **O que está no código** | [current-state.md](./current-state.md) |
| **UI / componentes** | [ui-design.md](./ui-design.md) |
| **Por que esta abordagem** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **Plano que foi executado** | [implementation-plan.md](./implementation-plan.md) |
| **O que ainda falta** | [improvements-backlog.md](./improvements-backlog.md) |

---

## Decisões em vigor

| Tópico | Decisão |
|--------|---------|
| Modelo de envio | Pipeline de attachment (`onFileUpload({ name, type, size, file })`) |
| Detecção do botão | `enumerateDevices()` → `kind === 'videoinput'`; sem `getUserMedia` no boot |
| Permissão | Só ao abrir o dialog |
| UI | `Dialog` montado no primeiro clique; Capture/Retake/Retry (`type="button"`) no corpo; Cancel e Use photo no footer |
| Ícone | `i-ph-camera` |
| Visibilidade | `hasWebcam` + (`showFileUpload` \|\| note) + `!isEditorDisabled` + `!isRecordingAudio` |
| Path | `widgets/conversation/WebcamCapture/` + `dashboard/composables/` |
| i18n | `en` + `pt_BR` (`CONVERSATION.WEBCAM_CAPTURE`) |
| Fork | Arquivos novos + `// FORK:` em `ReplyBox` e `ReplyBottomPanel` |
| Vídeo | `audio: false`, `facingMode: { ideal: 'user' }`, `ideal` 1280×720. Capturar só depois de um frame (`loadeddata` + `requestVideoFrameCallback`) |
| Arquivo | `image/jpeg` qualidade `0.92`, nome `webcam-${uuid}.jpg`. Aresta maior que 1920 é reduzida |
| Preview | `object-contain` — o que aparece é o frame inteiro que o JPEG guarda |
| Permissão já negada | Botão continua visível. Tooltip e alert usam `ERROR.PERMISSION` e o dialog não abre. Sem `permissions.query`, o clique abre o dialog |
| Troca de conversa | Fecha o dialog e solta stream pedido no clique |
| LED | Tracks param ao capturar, no erro de captura, no Retake, no close e no unmount |

---

## Fluxo

1. `useWebcamAvailability` no `ReplyBox.setup()` define `hasWebcam`.
2. O agente abre o dialog; `getUserMedia` pede a câmera.
3. Capture desenha o frame no canvas e gera o `File`. O stream para.
4. Use photo emite o arquivo; o ReplyBox anexa. O envio continua no botão Enviar.

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Inventário do código entregue |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções descartadas e decisões fechadas |
| [ui-design.md](./ui-design.md) | Componentes, estados, i18n |
| [implementation-plan.md](./implementation-plan.md) | Plano do MVP e checklist concluído |
| [improvements-backlog.md](./improvements-backlog.md) | P1/P2 ainda abertos |

---

*Última atualização: 24/out/2026 (tarde)*
