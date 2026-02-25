# Como Habilitar Transcrição de Áudio

## ⚠️ Problema: Erro 403 (Forbidden)

```
Audio transcription is not enabled for this account
```

## ✅ Solução Rápida via Rails Console (Recomendado)

1. Abra o Rails console:
```bash
cd /home/cesar/chatwoot
bundle exec rails console
```

2. Habilite para a conta específica (substitua `1` pelo ID da sua conta):
```ruby
account = Account.find(1)
account.audio_transcriptions = true
account.save!
puts "✅ Habilitado: #{account.audio_transcriptions}"
```

3. Para habilitar em todas as contas:
```ruby
Account.find_each do |account|
  account.update!(audio_transcriptions: true)
  puts "✅ Account #{account.id} - #{account.name}: enabled"
end
```

## 🎨 Solução via UI (Requer Feature Captain)

A interface de configuração `Audio Transcription` só aparece em **Settings → Account Settings** se a feature flag `captain_integration` estiver habilitada.

Para habilitar Captain + Audio Transcription via console:

```ruby
account = Account.find(1)

# Habilita a feature Captain (necessária para mostrar a UI)
account.enable_features!('captain_integration')

# Habilita Audio Transcription
account.audio_transcriptions = true
account.save!

puts "✅ Captain enabled: #{account.feature_captain_integration?}"
puts "✅ Audio transcription enabled: #{account.audio_transcriptions}"
```

Depois disso, a opção aparecerá em:
- **Settings → Account Settings → Audio Transcription** (toggle switch)

## Testando

Após habilitar:
1. Recarregue a página no navegador
2. Configure seu token Groq em Settings → Profile
3. Envie uma mensagem de áudio
4. Clique no botão de transcrição (ícone de ouvido)

## Troubleshooting

Se ainda receber erro 403:
- Limpe o cache do navegador
- Faça logout e login novamente
- Verifique os logs do Rails: `tail -f log/development.log`
