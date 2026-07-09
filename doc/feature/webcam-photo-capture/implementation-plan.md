# Webcam Photo Capture — Plano de Implementação (Chatwoot Fork)

Plano concreto para **abrir a webcam, tirar foto e anexar no chat**, reutilizando o pipeline de upload existente.

**Atualizado jul/2026** — decisões fechadas; UI alinhada ao codebase.

**Pré-requisitos:** [current-state.md](./current-state.md) · [implementation-decision-tree.md](./implementation-decision-tree.md) · [ui-design.md](./ui-design.md) · [improvements-backlog.md](./improvements-backlog.md)

---

## Contexto

O ReplyBox já anexa imagens (paperclip / paste) e já grava áudio gerando um `File`. Falta o fluxo de **captura via webcam** com botão condicional na toolbar.

## Objetivo

1. Mostrar botão de câmera na toolbar **somente** se houver webcam detectada
2. Abrir dialog com preview ao vivo, capturar foto e anexar
3. Enviar a imagem pelo fluxo normal de attachment (sem backend novo)
4. Integração merge-safe (`// FORK:` mínimo + arquivos novos)
5. i18n **en + pt_BR** na entrega

## Escopo MVP

### In scope

- Detecção `videoinput` via `enumerateDevices` (+ `devicechange`) no `ReplyBox.setup()`
- Botão `i-ph-camera` em `ReplyBottomPanel`
- Dialog de captura (stream → JPEG `File`, uuid no nome)
- Plug em `onFileUpload({ name, type, size, file })` / `attachFile`
- Visibilidade: webcam + (`showFileUpload` \|\| note) + `!isEditorDisabled` + `!isRecordingAudio`
- Constraints vídeo `ideal` 1280×720; Capture disabled até video ready
- Cleanup de `MediaStream` ao fechar/desmontar/após capture
- Tratamento de permissão negada / erro genérico (estado no dialog)
- i18n `en` + `pt_BR` (`conversation.json`)
- Itens **MVP-1…MVP-8** de [improvements-backlog.md](./improvements-backlog.md)

### Out of scope

- Feature flag global
- Backend / novos endpoints / novo `file_type`
- Troca de câmera, crop, filtros, vídeo
- `capture` attribute em `<input>` como solução principal
- Specs automatizados (salvo pedido explícito)
- Path sob `custom/app/javascript` (reservado a providers)

---

## Decisões de produto (resumo)

| # | Pergunta | Decisão |
|---|----------|---------|
| 1 | Como enviar? | `File` → `onFileUpload` |
| 2 | Quando mostrar botão? | `hasWebcam && eligible && !disabled && !recordingAudio` |
| 3 | Quando pedir permissão? | No open do dialog |
| 4 | Envio imediato? | Não — anexa e usuário clica Enviar |
| 5 | Formato | `image/jpeg` ~0.92, nome `webcam-${uuid}.jpg` |
| 6 | i18n | en + pt_BR |
| 7 | Resolução | ideal 1280×720 |

Detalhes: [implementation-decision-tree.md](./implementation-decision-tree.md) · [improvements-backlog.md](./improvements-backlog.md)

---

## Arquitetura

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
  Cap-->>Dialog: MediaStream → video
  Agent->>Dialog: Capture
  Cap-->>Dialog: File jpeg
  Dialog->>Box: emit capture(file)
  Box->>Upload: onFileUpload({ file })
  Upload-->>Box: attachFile → preview
```

---

## Fase 0 — Prep (rules / inventário)

1. Confirmar hooks FORK existentes no painel (share contact) como template
2. Confirmar `permissions_policy` sem bloqueio de `camera`
3. Não alterar `routes.rb`, Gemfile, package.json

---

## Fase 1 — Composables

### 1.1 `useWebcamAvailability`

**Arquivo:** `app/javascript/dashboard/composables/useWebcamAvailability.js`

Responsabilidades:

- `hasWebcam` (ref)
- `refreshDevices()` → `enumerateDevices()` → `some(d => d.kind === 'videoinput')`
- Guard: `navigator.mediaDevices` + `window.isSecureContext`
- Listener `devicechange` em `onMounted` / cleanup em `onUnmounted`
- Usado **somente** no `ReplyBox.setup()` (não no BottomPanel)

```js
// esboço
export function useWebcamAvailability() {
  const hasWebcam = ref(false);

  const refreshDevices = async () => {
    if (!window.isSecureContext || !navigator.mediaDevices?.enumerateDevices) {
      hasWebcam.value = false;
      return;
    }
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      hasWebcam.value = devices.some(d => d.kind === 'videoinput');
    } catch {
      hasWebcam.value = false;
    }
  };

  onMounted(() => {
    refreshDevices();
    navigator.mediaDevices?.addEventListener?.('devicechange', refreshDevices);
  });

  onUnmounted(() => {
    navigator.mediaDevices?.removeEventListener?.('devicechange', refreshDevices);
  });

  return { hasWebcam, refreshDevices };
}
```

### 1.2 `useWebcamCapture`

**Arquivo:** `app/javascript/dashboard/composables/useWebcamCapture.js`

Responsabilidades:

- `startStream()` / `stopStream()`
- `capturePhoto(videoEl)` → `Promise<File | null>`
- Estado: `isStarting`, `isVideoReady`, `error`, `stream`, `capturedFile`
- Constraints: `{ audio: false, video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } } }`
- Sempre `stopStream` no unmount / close / após capture (antes do confirm opcional: parar LED)
- Guard: `videoWidth/Height > 0`; `toBlob` null → erro

```js
// captura (esboço)
import getUuid from 'widget/helpers/uuid';

const canvas = document.createElement('canvas');
canvas.width = video.videoWidth;
canvas.height = video.videoHeight;
canvas.getContext('2d').drawImage(video, 0, 0);
const blob = await new Promise(resolve =>
  canvas.toBlob(resolve, 'image/jpeg', 0.92)
);
if (!blob) return null;
return new File([blob], `webcam-${getUuid()}.jpg`, { type: 'image/jpeg' });
```

---

## Fase 2 — UI

### 2.1 `WebcamCaptureView.vue`

- Bind `<video ref="videoEl" autoplay playsinline muted class="w-full rounded-lg bg-n-solid-3 aspect-video object-cover" />`
- Botão Capture / Retake (`NextButton`)
- Estados de loading/error com i18n

### 2.2 `WebcamCaptureDialog.vue`

- Wrapper `Dialog` (`components-next/dialog/Dialog.vue`)
- `defineExpose({ open })`
- Emit `capture` com o `File`
- No close: `stopStream()`

Espelhar estrutura de `ShareContact/ShareContactDialog.vue`.

---

## Fase 3 — Integração FORK (mínima)

### 3.1 `ReplyBottomPanel.vue`

```vue
<!-- FORK: webcam photo capture -->
<NextButton
  v-if="showWebcamButton"
  v-tooltip.top-end="$t('CONVERSATION.WEBCAM_CAPTURE.TOOLTIP')"
  icon="i-ph-camera"
  slate
  faded
  sm
  @click="$emit('openWebcamCapture')"
/>
```

- Prop `showWebcamButton`
- Emit `openWebcamCapture`
- Marcadores `// FORK:` / `<!-- FORK: -->` contíguos

### 3.2 `ReplyBox.vue`

- No `setup()` existente: `const { hasWebcam } = useWebcamAvailability();` e retornar `hasWebcam`
- Computed `showWebcamButton` (inclui `!isRecordingAudio`)
- Methods `openWebcamCaptureDialog` / `onWebcamPhotoCaptured`
- Passar prop + `@open-webcam-capture` no `ReplyBottomPanel`
- Montar `<WebcamCaptureDialog ref="..." @capture="..." />` ao lado do `ShareContactDialog`

**Não** reformatar o arquivo; só blocos FORK no topo dos métodos/computed e no template.

### 3.3 i18n

Atualizar:

- `app/javascript/dashboard/i18n/locale/en/conversation.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

Chaves em [ui-design.md](./ui-design.md).

---

## Fase 4 — Validação manual

| # | Caso | Esperado |
|---|------|----------|
| 1 | PC com webcam, HTTPS/localhost | Botão visível |
| 2 | Sem webcam / VM sem device | Botão oculto |
| 3 | Conectar/desconectar webcam | Botão aparece/some (`devicechange`) |
| 4 | Clique → permitir câmera | Preview ao vivo |
| 5 | Negar permissão | Erro i18n, sem crash |
| 6 | Capture → Use photo | Thumb em `AttachmentPreview` |
| 7 | Enviar | Mensagem com imagem no canal |
| 8 | Fechar dialog / Retake / X / outside | LED da câmera apaga |
| 9 | Canal sem `showFileUpload` | Botão oculto |
| 10 | `isEditorDisabled` (ex.: 24h WA) | Botão oculto |
| 11 | Private note com upload | Botão ok se houver webcam |
| 12 | Página HTTP (não secure) | Botão oculto |
| 13 | Durante `isRecordingAudio` | Botão oculto |
| 14 | Capture antes de video ready | Botão Capture disabled |
| 15 | Webcam alta resolução | JPEG via constraints 1280×720 |
| 16 | Locale pt_BR | Tooltip/modal em português |

---

## Ordem de implementação sugerida

1. Composables (`availability` + `capture`)
2. `WebcamCaptureView` + `WebcamCaptureDialog`
3. Hooks FORK em `ReplyBottomPanel` + `ReplyBox.setup()`
4. i18n en + pt_BR
5. Smoke manual (tabela acima)

---

## Project rules checklist

| Rule | Check |
|------|-------|
| fork-workflow | Arquivos novos + FORK mínimo; sem editar corpo upstream além do hook |
| architecture | Lógica no composable; Vue só wiring |
| vue-frontend | `<script setup>`, Tailwind only, i18n |
| chatwoot-core | MVP; sem specs a menos que pedido; só en |
| Sem docs extras | Esta pasta `doc/feature/` é o artefato pedido |

---

## Riscos e mitigações

| Risco | Mitigação |
|-------|-----------|
| `enumerateDevices` sem videoinput listado até permission | Aceitar no MVP; botão pode faltar em browsers rígidos até 1ª permissão — documentar; não forçar GUM no boot |
| Stream vazando | `stopStream` em close, unmount, retake, confirm |
| Arquivo grande | Limites já no `onFileUpload`; JPEG 0.92 |
| Merge conflict em ReplyBox | Blocos FORK curtos e isolados |
| HTTP não-seguro | `hasWebcam = false` se `!isSecureContext` |

---

## Follow-ups (pós-MVP)

Ver [improvements-backlog.md](./improvements-backlog.md) (P1/P2): refresh pós-permissão, `permissions.query`, downscale, lazy mount, seletor de câmera, etc.

---

## Definição de pronto (MVP)

- [ ] Botão só aparece com webcam detectada + canal elegível + não gravando áudio
- [ ] Dialog captura JPEG e anexa no ReplyBox
- [ ] Envio funciona como imagem normal
- [ ] Stream sempre liberado ao fechar / após capture
- [ ] Capture disabled até video ready; blob null tratado
- [ ] Constraints 1280×720; nome com uuid
- [ ] i18n en + pt_BR completo
- [ ] Marcadores FORK nos pontos de integração
- [ ] Sem mudanças de backend / sem path `custom/` para esta feature
- [ ] Itens MVP-1…MVP-8 do backlog atendidos

---

*Última atualização: jul/2026*
