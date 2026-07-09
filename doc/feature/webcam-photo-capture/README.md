# Webcam Photo Capture — Documentação

Plano para **captura de foto via webcam no ReplyBox**, enviando a imagem como attachment normal da conversa.

**Estado:** implementado (MVP) · jul/2026

| Área | Status |
|------|--------|
| Upload / envio de imagem | ✅ Existe (`onFileUpload` → `attachFile`) |
| Preview de anexos | ✅ Existe (`AttachmentPreview`) |
| Gravação de áudio (análogo) | ✅ Existe (`AudioRecorder`) |
| Detecção de webcam | ✅ `useWebcamAvailability` |
| Captura + dialog de preview | ✅ `WebcamCapture/` |
| Botão na toolbar | ✅ `ReplyBottomPanel` (`i-ph-camera`) |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementar agora** | [implementation-plan.md](./implementation-plan.md) |
| **UI / componentes** | [ui-design.md](./ui-design.md) |
| **Por que esta abordagem** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **O que já existe** | [current-state.md](./current-state.md) |
| **Revisão / melhorias** | [improvements-backlog.md](./improvements-backlog.md) |

---

## Decisões fechadas

| Tópico | Decisão |
|--------|---------|
| Modelo de envio | Reusar pipeline de attachment de imagem (`onFileUpload`) |
| Detecção do botão | `enumerateDevices()` → `kind === 'videoinput'` |
| Permissão | Pedir só no clique (abrir dialog), não na listagem |
| UI | `Dialog` + preview ao vivo + capturar/confirmar |
| Ícone ReplyBox | `i-ph-camera` (Phosphor, igual aos demais) |
| Visibilidade | Webcam + (`showFileUpload` \|\| note) + `!disabled` + `!isRecordingAudio` |
| Path dos arquivos | `widgets/conversation/WebcamCapture/` + composables em `dashboard/composables/` (como Share Contact) |
| Backend | Nenhum endpoint novo |
| Feature flag | Não no MVP |
| i18n | **en + pt_BR** (padrão Share Contact neste fork) |
| Fork | Composables/UI novos + `// FORK:` mínimo em `ReplyBottomPanel` / `ReplyBox` |
| Constraints vídeo | `ideal` 1280×720, `audio: false` |

---

## Recomendação técnica (resumo)

1. Composable detecta `videoinput` e controla stream/`getUserMedia`
2. Dialog captura frame → `File` (`image/jpeg`)
3. Mesmo fluxo do paperclip/áudio: `onFileUpload` → preview → Enviar
4. Botão na toolbar após anexo / share contact, estilo `NextButton slate faded sm`

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Inventário ReplyBox, upload, lacunas |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções, decisões de produto/técnicas |
| [ui-design.md](./ui-design.md) | Componentes, estilos, i18n, wireframes |
| [implementation-plan.md](./implementation-plan.md) | Fases, arquivos, testes, fork |
| [improvements-backlog.md](./improvements-backlog.md) | MVP obrigatório + P1/P2 da revisão |

---

*Última atualização: jul/2026*
