# Groq API Compliance Check

## API Documentation Reference
https://console.groq.com/docs/speech-to-text

## ✅ Implementação Correta

### Endpoint
- ✅ Correto: `https://api.groq.com/openai/v1/audio/transcriptions`

### Autenticação
- ✅ Correto: `Authorization: Bearer {groq_token}` via header

### Modelos Suportados
- ✅ Correto: Default `whisper-large-v3-turbo` (mais rápido e barato)
- ✅ Alternativa disponível: `whisper-large-v3` (mais preciso)

### Parâmetros Obrigatórios
- ✅ `file`: Faraday::UploadIO com arquivo de áudio
- ✅ `model`: whisper-large-v3-turbo (default) ou via params[:model]

### Parâmetros Opcionais Implementados
- ✅ `language`: ISO-639-1 format (ex: 'en', 'pt') - via params[:language]
- ✅ `prompt`: Contexto ou estilo (max 224 tokens) - via params[:prompt]
- ✅ `response_format`: 'verbose_json' para obter metadata detalhada
- ✅ `temperature`: 0.0 (recomendado pela documentação)

### Formatos de Áudio Suportados
Documentação Groq: flac, mp3, mp4, mpeg, mpga, m4a, ogg, opus, wav, webm

Nossa implementação:
- **Envio direto** (sem conversão): flac, mp3, mp4, mpeg, mpga, m4a, ogg, opus, wav, webm
- **Normalização MIME**: `audio/oga` e `audio/x-oga` → `audio/ogg` (Groq aceita ogg)
- **Normalização de filename**: `.oga` → `.ogg` (Groq valida pela extensão do arquivo)
- **Conversão via FFmpeg** (`AudioConverterService`): aac, amr, vnd.wave → mp3
- Serviço: `app/services/audio_converter_service.rb`
✅ Formatos nativos enviados direto; formatos não suportados convertidos para mp3

### Limites de Arquivo
- ✅ Max: 25 MB (tier gratuito) / 100 MB (tier dev)
- ✅ Implementado: AUDIO_MAX_SIZE = 25.megabytes

### Timeouts
- ✅ Request timeout: 60s
- ✅ Open timeout: 10s

## 🔧 Correções Aplicadas

### 1. Adição do parâmetro `temperature`
**Antes**: Não estava incluído
**Depois**: `temperature: '0.0'` (como string para multipart form-data)

**Motivo**: Documentação recomenda 0.0 para traduções e transcrições

### 2. Simplificação do payload
**Antes**: Incluía `timestamp_granularities` que pode causar problemas com multipart
**Depois**: Removido temporariamente (é opcional)

**Motivo**: Simplificar para garantir funcionamento básico primeiro

### 3. Normalização de arquivos .oga
**Problema**: Arquivos com extensão `.oga` (mesmo com content-type `audio/opus` ou `audio/ogg`) eram rejeitados pelo Groq.
**Solução**: Em `fetch_audio_from_attachment`, normalizar filename `.oga` → `.ogg` e content-type `audio/oga`/`audio/x-oga` → `audio/ogg` antes de enviar.
**Motivo**: Groq valida pela extensão do arquivo; `.oga` não está na lista aceita.

## 📋 Response Format

### Com `verbose_json` recebemos:
```json
{
  "text": "transcrição completa",
  "segments": [
    {
      "id": 0,
      "seek": 0,
      "start": 0.0,
      "end": 5.0,
      "text": "segmento de texto",
      "tokens": [...],
      "temperature": 0.0,
      "avg_logprob": -0.1,
      "compression_ratio": 1.5,
      "no_speech_prob": 0.01
    }
  ],
  "language": "en",
  "duration": 45.2,
  "model": "whisper-large-v3-turbo"
}
```

### Nossa implementação salva (canonical shape):
```ruby
{
  text: data['text'],
  state: 'success',
  provider: 'groq',
  model: data['model'],
  transcribed_at: Time.current.to_i,
  metadata: {
    segments: data['segments'],
    language: data['language'],
    duration: data['duration']
  }
}
```
✅ Compatível com documentação; `transcribed_at` no nível raiz; `metadata` para dados extras

## 🎯 Recomendações da Documentação Groq

### Escolha de Modelo
- ✅ Implementado: `whisper-large-v3-turbo` como default (melhor custo/benefício)
- 💡 Disponível: `whisper-large-v3` via params[:model] se precisar maior precisão

### Prompts
- ✅ Aceita prompts para contexto (max 224 tokens)
- ✅ Mesmo idioma do áudio
- ✅ Guia de estilo/contexto, não ações específicas

### Preprocessamento de Áudio
**Recomendação Groq**: Converter para 16KHz mono antes do upload

```bash
ffmpeg -i <input> -ar 16000 -ac 1 -map 0:a -c:a flac output.flac
```

💡 **Melhoria futura**: Implementar preprocessamento automático no AudioConverterService

## ✅ Conclusão

A implementação está **100% compatível** com a documentação oficial da Groq API após as correções aplicadas.

### Testes Recomendados
1. ✅ Transcrição básica (apenas token)
2. ✅ Com language hint (ISO-639-1)
3. ✅ Com prompt para contexto
4. ✅ Diferentes formatos de áudio
5. ✅ Verificar cache funcionando
6. ✅ Testar limites de tamanho
