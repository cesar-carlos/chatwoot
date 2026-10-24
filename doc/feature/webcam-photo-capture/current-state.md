# Webcam Photo Capture — Estado atual

Inventário do que o dashboard faz hoje. O MVP está no código; follow-ups abertos estão em [improvements-backlog.md](./improvements-backlog.md).

---

## Arquivos

| Peça | Arquivo |
|------|---------|
| Detecção | `app/javascript/dashboard/composables/useWebcamAvailability.js` |
| Stream e JPEG | `app/javascript/dashboard/composables/useWebcamCapture.js` |
| Dialog | `app/javascript/dashboard/components/widgets/conversation/WebcamCapture/WebcamCaptureDialog.vue` |
| Preview | `.../WebcamCapture/WebcamCaptureView.vue` |
| Toolbar | `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` |
| Wiring | `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` |
| i18n | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/conversation.json` |

Não há spec automatizado, endpoint novo, `file_type` novo nem feature flag.

---

## Visibilidade do botão

`ReplyBox#showWebcamButton`:

```js
if (this.isEditorDisabled || this.isRecordingAudio) return false;
if (!this.hasWebcam) return false;
return this.showFileUpload || this.isOnPrivateNote;
```

`hasWebcam` vem de `useWebcamAvailability()` no `setup()` já existente. O BottomPanel só recebe a prop `showWebcamButton` e emite `openWebcamCapture`.

O botão fica depois do share contact e antes do microfone (`i-ph-camera`, `NextButton` `slate` `faded` `sm`).

Com o Copilot ativo, o `ReplyBottomPanel` inteiro sai da tela (`CopilotReplyBottomPanel`). Não há checagem extra de `copilot.isActive` dentro de `showWebcamButton`.

### Quando `hasWebcam` é falso

- Sem `window.isSecureContext` (página HTTP)
- Sem `navigator.mediaDevices.enumerateDevices`
- Nenhum device `videoinput`
- `enumerateDevices` rejeita

Listener `devicechange` chama `refreshDevices` no mount e remove no unmount. `getUserMedia` não roda nessa etapa.

Depois que a câmera abre com sucesso, o dialog emite `devicesGranted` e o ReplyBox chama `refreshWebcamDevices`. Isso preenche labels que o browser só libera após a permissão.

`permissions.query({ name: 'camera' })` marca `isCameraDenied` quando o estado é `denied`. O botão continua na toolbar. O tooltip passa a ser `ERROR.PERMISSION` e o clique mostra o mesmo texto num alert, sem abrir o dialog. Se a API não existe ou a query rejeita (Firefox/Safari), `isCameraDenied` fica falso e o clique abre o dialog.

### Canais

`showFileUpload` cobre Web Widget, Facebook, WhatsApp, API, Email, SMS, Telegram, LINE, Instagram e TikTok quando `image_send` permite (default `true` se a capability não vier).

Nota privada também mostra o botão, mesmo sem `showFileUpload`.

`isEditorDisabled` esconde o botão na janela de 24h de WhatsApp/API (`can_reply`), em Wavoip fora de nota, e na restrição de reply só do assignee. Gateway WhatsApp self-hosted não usa a janela de 24h.

---

## Dialog

`WebcamCaptureDialog` monta no primeiro clique (`webcamDialogMounted`). O clique chama `primeWebcamStream()` antes do `nextTick`, para o `getUserMedia` continuar no gesto do usuário. Aberturas seguintes chamam `open()` no mesmo turno. Trocar de conversa chama `close()` e `releasePrimedWebcamStream()`.

| Ação | Onde | Efeito |
|------|------|--------|
| Cancel | Footer do `Dialog` | `reset()` — para tracks e revoga o object URL |
| Use photo | Footer confirm | Desabilitado até `capturedFile`; emite `capture` e fecha |
| Capture | Corpo, `type="button"` | `canvas` → JPEG; para o stream (LED apaga). Falha de frame, contexto ou `toBlob` também para o stream |
| Retake | Corpo, `type="button"` | Limpa o preview e chama `startStream` de novo |
| Retry | Corpo, `type="button"`, só no erro | `startCamera()` de novo |
| Close / unmount | `@close` e `onUnmounted` | `reset()` |

`open()` faz `reset()`, abre o `Dialog` e chama `startStream()` no mesmo turno. No primeiro clique o `getUserMedia` já foi disparado por `primeWebcamStream()`; o `nextTick` só espera o componente existir para adotar esse request. O `<video>` liga o `srcObject` quando o slot do dialog monta.

Se o dialog fecha enquanto o prompt de permissão está aberto, `startGeneration` invalida o request. O stream que chegar depois tem os tracks parados e não é guardado. Um JPEG que termina depois do close também é descartado.

Constraints:

```js
{
  audio: false,
  video: {
    facingMode: { ideal: 'user' },
    width: { ideal: 1280 },
    height: { ideal: 720 },
  },
}
```

Erros de mídia:

| `DOMException.name` | Chave i18n |
|---------------------|------------|
| `NotAllowedError`, `PermissionDeniedError` | `ERROR.PERMISSION` |
| `NotFoundError`, `DevicesNotFoundError` | `ERROR.NOT_FOUND` |
| demais, contexto inseguro, canvas/`toBlob` nulo | `ERROR.GENERIC` |

O botão Capture fica `disabled` até um frame existir. `loadeddata` (e `resize`, se a dimensão chegar depois) espera `requestVideoFrameCallback` quando o browser tem esse método. Sem ele, `loadeddata` com `videoWidth` e `videoHeight` libera o botão.

Preview ao vivo e a imagem capturada usam `object-contain` numa caixa 16:9. Não há espelhamento CSS. O JPEG é o frame inteiro, não o recorte da caixa.

Se a maior aresta passa de 1920, o canvas reduz mantendo a proporção (`imageSmoothingQuality: 'high'`) antes do `toBlob`.

---

## Anexo

```js
onWebcamPhotoCaptured(file) {
  this.onFileUpload({
    name: file.name,
    type: file.type,
    size: file.size,
    file,
  });
}
```

Nome: `webcam-${getUuid()}.jpg` (`widget/helpers/uuid`). Tipo `image/jpeg`, qualidade `0.92`. O agente ainda clica Enviar. Limites de tamanho e MIME continuam em `useFileUpload` / canal. O teto do canvas é 1920 na maior aresta.

---

## Permissão de câmera no servidor

`config/initializers/permissions_policy.rb` deixa o bloco inteiro comentado, inclusive `camera :none`. O header não bloqueia `getUserMedia`.

---

## FORK

Marcadores `// FORK: webcam photo capture` / `<!-- FORK: webcam photo capture -->` em:

- `ReplyBox.vue` — import, `setup()`, computed, methods, template
- `ReplyBottomPanel.vue` — prop, emit, botão

Os composables e os dois Vue de `WebcamCapture/` são arquivos novos, sem marcador no corpo.

---

Specs: `composables/spec/useWebcamAvailability.spec.js`, `composables/spec/useWebcamCapture.spec.js`, `WebcamCapture/WebcamCaptureView.spec.js`.

*Última atualização: 24/out/2026 (tarde)*
