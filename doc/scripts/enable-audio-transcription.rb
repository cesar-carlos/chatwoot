#!/usr/bin/env ruby
# frozen_string_literal: true

# Script para habilitar transcrição de áudio em uma ou todas as contas
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
  puts "✅ Account #{account.id} - #{account.name}: Audio transcription enabled"
rescue StandardError => e
  puts "❌ Account #{account.id} - #{account.name}: Failed - #{e.message}"
end

if account_id.present?
  # Habilita em uma conta específica
  account = Account.find(account_id)
  enable_for_account(account)
  
  puts "\n📋 Status:"
  puts "   Audio Transcription: #{account.audio_transcriptions ? '✅ Enabled' : '❌ Disabled'}"
  
  puts "\n💡 Dica: Configure o Token Groq nas configurações do usuário:"
  puts "   Settings → Profile → Groq API Token"
else
  # Habilita em todas as contas
  puts "Habilitando audio transcription em todas as contas...\n"
  
  Account.find_each do |account|
    enable_for_account(account)
  end
  
  total = Account.count
  enabled = Account.where("settings->>'audio_transcriptions' = 'true'").count
  
  puts "\n📊 Resumo:"
  puts "   Total de contas: #{total}"
  puts "   Com audio transcription: #{enabled}"
end
