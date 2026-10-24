# Webcam Photo Capture — Backlog

O MVP e o P1 estão no código. Aberto ficou o P2. O contrato atual está em [current-state.md](./current-state.md).

---

## Entregue

| Item | O que ficou |
|------|-------------|
| MVP-1 | UI em `widgets/conversation/WebcamCapture/`; composables em `dashboard/composables/` |
| MVP-2 | `en` + `pt_BR`, com `MODAL.RETRY` |
| MVP-3 | `useWebcamAvailability` no `setup()` do ReplyBox; BottomPanel só recebe a prop |
| MVP-4 | `onFileUpload({ name, type, size, file })`, uuid, guard de `videoWidth` e de `toBlob` null |
| MVP-5 | `ideal` 1280×720 e `facingMode: { ideal: 'user' }` |
| MVP-6 | Botão oculto com `isEditorDisabled` ou `isRecordingAudio` |
| MVP-7 | Cancel e Use photo no footer; Capture, Retake e Retry no corpo; `reset()` no close |
| MVP-8 | Detecção só no ReplyBox |
| Corrida | `startGeneration` descarta `getUserMedia` que resolve depois do close |
| Permissão | `@devices-granted` → `refreshWebcamDevices` |

---

## P1 — feito em 24/out/2026

| ID | O que ficou |
|----|-------------|
| P1-2 | `permissions.query({ name: 'camera' })`. `denied` troca o tooltip, o clique alerta e não abre o dialog. Query ausente ou rejeitada não esconde o botão |
| P1-3 | Maior aresta acima de 1920 é reduzida no canvas antes do `toBlob` |
| P1-4 | `WebcamCaptureDialog` só monta no primeiro clique. O clique chama `primeWebcamStream()` para o `getUserMedia` não esperar o `nextTick` |
| P1-5 | Specs de disponibilidade, captura (prime, geração, downscale, blob nulo) e da view (frame e `type="button"`) |

---

## P2

| ID | Item | Nota |
|----|------|------|
| P2-1 | Seletor quando há mais de um `videoinput` | Hoje o browser escolhe, com `facingMode` ideal `user` |
| P2-2 | Preview espelhado e JPEG sem espelho | Hoje os dois são o frame cru, sem CSS mirror |
| P2-3 | Atalho de teclado | Não há |
| P2-4 | Feature flag | Não há |
| P2-5 | `<input capture="user">` no mobile | Não substitui o dialog no desktop |
| P2-6 | Gravação de vídeo curta | Fora do modelo de foto |

P1-1 (refresh depois da permissão) já estava em `@devices-granted`. P1-2 a P1-5 foram para a tabela acima.

---

## Correções da revisão de 24/out/2026 (tarde)

| Caso | Código |
|------|--------|
| Capture/Retake/Retry dentro do `<form>` do Dialog | `type="button"` |
| Preview `object-cover` cortava 4:3 | `object-contain` |
| JPEG preto no `loadedmetadata` | `loadeddata` + `requestVideoFrameCallback` |
| `toBlob` nulo deixava o LED aceso | `stopStream()` no erro de captura |
| `getUserMedia` depois do `nextTick` | `primeWebcamStream()` no clique |
| Dialog aberto ao trocar de conversa | `close()` + `releasePrimedWebcamStream()` |

O restante da matriz do plano (secure context, áudio, video ready, pt_BR, close) está coberto pelo código descrito em [implementation-plan.md](./implementation-plan.md).

---

*Última atualização: 24/out/2026 (tarde)*
