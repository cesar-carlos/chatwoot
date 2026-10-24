# Webcam Photo Capture — Plano de implementação

Plano do MVP. **Executado.** O comportamento em produção está em [current-state.md](./current-state.md). Este arquivo guarda o recorte que foi combinado e o que o esboço não previa.

**Atualizado 24/out/2026.**

---

## Objetivo

1. Botão de câmera só com webcam detectada e canal/nota elegível
2. Dialog com preview, captura e confirmação
3. Envio pelo attachment existente
4. `// FORK:` mínimo + arquivos novos
5. i18n `en` + `pt_BR`

## Escopo que entrou

- `enumerateDevices` + `devicechange` no `ReplyBox.setup()`
- Botão `i-ph-camera` em `ReplyBottomPanel`
- JPEG com uuid, Capture disabled até o vídeo ter dimensão
- `onFileUpload({ name, type, size, file })`
- Visibilidade: webcam + (`showFileUpload` \|\| note) + `!isEditorDisabled` + `!isRecordingAudio`
- Constraints `ideal` 1280×720 e `facingMode: { ideal: 'user' }`
- `stopStream` no close, unmount, capture e antes de reabrir
- Erro de permissão / device / genérico dentro do dialog, com Retry
- Itens MVP-1…MVP-8 de [improvements-backlog.md](./improvements-backlog.md)

## Ficou de fora do MVP

- Feature flag
- Backend, endpoint, `file_type`
- Troca de câmera, crop, filtros, vídeo, espelho, atalho e `<input capture>`
- Path em `custom/app/javascript`

`permissions.query`, downscale, lazy mount e specs entraram na revisão de 24/out/2026 (tarde). Ver [improvements-backlog.md](./improvements-backlog.md).

---

## Sequência entregue

```mermaid
sequenceDiagram
  participant Agent as ReplyBottomPanel
  participant Box as ReplyBox
  participant Avail as useWebcamAvailability
  participant Dialog as WebcamCaptureDialog
  participant Cap as useWebcamCapture
  participant Upload as onFileUpload

  Avail->>Box: hasWebcam
  Box->>Agent: showWebcamButton
  Agent->>Box: openWebcamCapture
  Box->>Dialog: open()
  Dialog->>Cap: startStream()
  Cap-->>Dialog: MediaStream
  Dialog->>Box: devicesGranted
  Box->>Avail: refreshDevices()
  Dialog->>Cap: capturePhoto(video)
  Cap-->>Dialog: File jpeg + stop tracks
  Dialog->>Box: capture(file)
  Box->>Upload: onFileUpload({ name, type, size, file })
```

---

## Deltas do esboço original

O plano de jul/2026 descrevia o caminho certo. O código fechou estes pontos que o esboço deixava solto:

| Esboço | Código |
|--------|--------|
| `facingMode: 'user'` | `facingMode: { ideal: 'user' }` |
| Erro só com alert e fechar | Estado no dialog + botão Retry |
| Refresh de devices “depois” | `@devices-granted` no ReplyBox |
| Prompt de permissão sem corrida | `startGeneration` solta o stream órfão |
| pt_BR sem `RETRY` no wireframe | `MODAL.RETRY` em `en` e `pt_BR` |
| Checklist “só locale en” | Contradição removida: a entrega é `en` + `pt_BR` |
| Copilot como hide opcional | O painel do Copilot substitui o `ReplyBottomPanel`; o botão some junto |

---

## Validação manual prevista

Não há spec. A tabela abaixo é o roteiro de smoke, não um registro de execução automática.

| # | Caso | Esperado |
|---|------|----------|
| 1 | PC com webcam, HTTPS/localhost | Botão visível |
| 2 | Sem webcam | Botão oculto |
| 3 | Conectar/desconectar | `devicechange` mostra ou esconde |
| 4 | Permitir câmera | Preview ao vivo |
| 5 | Negar permissão | `ERROR.PERMISSION` e Retry, sem crash |
| 6 | Capture → Use photo | Thumb no preview de anexo |
| 7 | Enviar | Mensagem com imagem |
| 8 | Fechar, Retake, X, Cancel | LED apaga; Retake religa |
| 9 | Canal sem `showFileUpload` e sem nota | Botão oculto |
| 10 | `isEditorDisabled` | Botão oculto |
| 11 | Nota privada | Botão visível se houver webcam |
| 12 | HTTP | Botão oculto |
| 13 | `isRecordingAudio` | Botão oculto |
| 14 | Capture antes do vídeo pronto | Botão disabled |
| 15 | Device que honra o `ideal` | Frame perto de 1280×720 |
| 16 | Locale `pt_BR` | Tooltip e modal em português |
| 17 | Fechar durante o prompt | Stream que chegar depois é descartado |

---

## Definição de pronto

- [x] Botão só com webcam, canal ou nota elegível, editor livre e sem áudio gravando
- [x] Dialog gera JPEG e anexa no ReplyBox
- [x] Envio é imagem normal
- [x] Stream liberado ao fechar e após capture
- [x] Capture disabled até video ready; blob null vira erro genérico
- [x] Constraints 1280×720; nome com uuid
- [x] i18n `en` + `pt_BR`, inclusive Retry
- [x] Marcadores `FORK` nos pontos de integração
- [x] Sem backend e sem path `custom/` para esta feature
- [x] MVP-1…MVP-8

---

*Última atualização: 24/out/2026*
