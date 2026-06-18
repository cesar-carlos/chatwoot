#!/usr/bin/env ruby
# frozen_string_literal: true

# Habilita transcrição AUTOMÁTICA de áudio (modo original OpenAI) em uma ou todas as contas.
# Isso NÃO configura transcrição manual Groq — para Groq, use Settings → Profile → Groq API Token.
# Quando este modo está ativo, a transcrição manual Groq fica desabilitada (mutual exclusion).
#
# Uso:
#   bundle exec rails runner doc/scripts/enable-audio-transcription.rb [account_id]
#
# Exemplos:
#   bundle exec rails runner doc/scripts/enable-audio-transcription.rb           # Habilita em todas as contas
#   bundle exec rails runner doc/scripts/enable-audio-transcription.rb 1         # Habilita apenas na conta ID 1

account_id = ARGV[0]

def enable_for_account(account)
  account.audio_transcriptions = true
  account.save!
  puts "✅ Account #{account.id} - #{account.name}: Automatic audio transcription enabled (OpenAI)"
rescue StandardError => e
  puts "❌ Account #{account.id} - #{account.name}: Failed - #{e.message}"
end

if account_id.present?
  account = Account.find(account_id)
  enable_for_account(account)

  puts "\n📋 Status:"
  puts "   Automatic Audio Transcription: #{account.audio_transcriptions ? '✅ Enabled' : '❌ Disabled'}"
  puts "\n💡 Manual Groq transcription is disabled while automatic mode is active."
else
  puts "Habilitando transcrição automática de áudio em todas as contas...\n"

  Account.find_each do |account|
    enable_for_account(account)
  end

  total = Account.count
  enabled = Account.where("settings->>'audio_transcriptions' = 'true'").count

  puts "\n📊 Resumo:"
  puts "   Total de contas: #{total}"
  puts "   Com transcrição automática: #{enabled}"
end
