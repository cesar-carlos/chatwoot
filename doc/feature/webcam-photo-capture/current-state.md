# Webcam Photo Capture — Estado Atual

Inventário do que já existe no codebase para **anexar e enviar imagens no ReplyBox**, e o que falta para captura via webcam.

---

## O que já funciona

### Toolbar do ReplyBox

| Item | Local |
|------|-------|
| Barra de ações | `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` |
| Orquestração | `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` |
| Botões atuais | emoji, paperclip, share contact (FORK), mic, signature, quoted reply, templates, video call, article |

Padrão visual dos botões:

```vue
<NextButton
  v-tooltip.top-end="..."
  icon="i-ph-..."
  slate
  faded
  sm
  @click="..."
/>
```

### Upload de arquivo / imagem

| Item | Local |
|------|-------|
| Input de arquivo | `FileUpload` em `ReplyBottomPanel.vue` |
| Upload (mixin legado) | `app/javascript/dashboard/mixins/fileUploadMixin.js` |
| Upload (composable) | `app/javascript/dashboard/composables/useFileUpload.js` |
| Anexar ao estado | `ReplyBox#attachFile` |
| Preview | `AttachmentsPreview.vue` |
| Envio | `getMultipleMessagesPayload` / payload com `files` |

Fluxo atual:

```
File (usuário) → onFileUpload → DirectUpload (opcional) → attachFile → attachedFiles[] → Enviar
```

### Análogo: gravação de áudio

| Item | Local |
|------|-------|
| UI recorder | `WootWriter/AudioRecorder.vue` |
| Toggle | `ReplyBox#toggleAudioRecorder` |
| Resultado | Gera `File` + `isVoiceMessage: true` → `onFileUpload` |

A webcam deve seguir o mesmo padrão: **gerar um `File` e reentrar no pipeline de upload**, sem API nova.

### Canais que aceitam anexo (`showFileUpload`)

Em `ReplyBox.vue`:

- Web Widget, Facebook, WhatsApp, API, Email, SMS, Telegram, LINE, Instagram
- TikTok (quando `image_send` capability permite)

O botão de webcam deve respeitar a mesma condição (ou subset), pois o envio é attachment de imagem.

### Media APIs já usadas no projeto

| Uso | Local | Nota |
|-----|-------|------|
| `getUserMedia({ audio: true })` | `composables/useWebRtcCallSession.js` | Chamadas de voz — não captura foto |
| `allow="camera;microphone;..."` | Widget / Dyte iframe | Só iframe de call, não ReplyBox |
| Permissions Policy | `config/initializers/permissions_policy.rb` | `camera` comentado — **não bloqueia** |

**Não existe** hoje: `enumerateDevices` para `videoinput`, preview de webcam, nem captura de frame no dashboard.

---

## FORK de referência (mesmo painel)

O botão **Share Contact** já é um FORK na mesma toolbar — padrão a espelhar:

| Peça | Arquivo |
|------|---------|
| Prop + botão | `ReplyBottomPanel.vue` (`showShareContactButton`, emit `openShareContact`) |
| Visibilidade + open | `ReplyBox.vue` (`showShareContactButton`, `openShareContactDialog`) |
| Dialog | `widgets/conversation/ShareContact/ShareContactDialog.vue` |
| Form | `ShareContact/ShareContactForm.vue` |
| i18n | `CONVERSATION.SHARE_CONTACT.*` |

---

## Modelo de dados / backend

- Imagem capturada = attachment de arquivo normal (`image/jpeg` ou `image/png`)
- Sem novo `file_type`, sem novo endpoint, sem mudança em `MessageBuilder`
- Limites de tamanho/MIME já aplicados por `useFileUpload` / `getMaxUploadSizeByChannel` / `getAllowedFileTypesByChannel`

---

## Lacunas (o que falta)

| Lacuna | Impacto |
|--------|---------|
| Detecção de `videoinput` | Botão não pode aparecer só “sempre” |
| UI de captura (preview + shutter) | Usuário não tem como tirar a foto |
| Conversão stream → `File` | Não entra no `onFileUpload` |
| Cleanup de `MediaStream` | Risco de LED da câmera ficar ligado |
| i18n do botão/dialog | Strings bare proibidas pelas rules |
| Hooks `// FORK:` no ReplyBox/BottomPanel | Integração merge-safe |

---

## Constraints de ambiente

| Constraint | Detalhe |
|------------|---------|
| HTTPS / localhost | `getUserMedia` exige contexto seguro |
| Permissão do browser | Labels de device podem vir vazios até o user autorizar |
| Sem webcam | Botão oculto |
| Permissão negada | Alert + fechar dialog (padrão do áudio) |
| Editor disabled | Botão oculto (`isEditorDisabled`, janela 24h WhatsApp, etc.) |

---

## Conclusão

A base de **envio** já está pronta. O trabalho é 100% frontend: detectar dispositivo, capturar frame, e plugar no `onFileUpload` existente, com integração mínima FORK na toolbar.
