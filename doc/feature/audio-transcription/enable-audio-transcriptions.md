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

## 🎨 Solução via UI

A interface de configuração `Audio Transcription` aparece em **Settings → Account Settings**.

Basta acessar a página e usar o toggle switch para habilitar/desabilitar.

**Nota**: A feature de transcrição é independente e NÃO requer Captain ou outras features.

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
