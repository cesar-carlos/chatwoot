# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter do
  describe '.canonicalize_data' do
    it 'maps Info/Message PascalCase payloads' do
      data = {
        'Info' => {
          'ID' => 'MSG123',
          'Chat' => '5511999999999@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false,
          'PushName' => 'Maria',
          'Timestamp' => 1_699_999_999
        },
        'Message' => {
          'conversation' => 'Hello'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:id]).to eq('MSG123')
      expect(result[:key][:remoteJidAlt]).to eq('5511999999999@s.whatsapp.net')
      expect(result[:message][:conversation]).to eq('Hello')
      expect(result[:pushName]).to eq('Maria')
    end

    it 'unwraps ephemeral nested messages' do
      data = {
        'Info' => {
          'ID' => 'EPH1',
          'Chat' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false
        },
        'Message' => {
          'ephemeralMessage' => {
            'message' => {
              'conversation' => 'Hidden text'
            }
          }
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:message][:conversation]).to eq('Hidden text')
    end

    it 'unwraps documentWithCaptionMessage payloads from Evolution Go' do
      data = {
        'Info' => {
          'ID' => 'DOC-CAPTION-1',
          'Chat' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false,
          'Type' => 'DocumentMessage'
        },
        'Message' => {
          'documentWithCaptionMessage' => {
            'message' => {
              'documentMessage' => {
                'URL' => 'https://mmg.whatsapp.net/example',
                'mimetype' => 'application/pdf',
                'fileName' => 'boleto.pdf',
                'caption' => 'Documento solicitado'
              }
            }
          }
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:message][:documentMessage][:fileName]).to eq('boleto.pdf')
      expect(result[:message][:documentMessage][:caption]).to eq('Documento solicitado')
      expect(result[:message][:documentWithCaptionMessage]).to be_nil
    end

    it 'unwraps botInvokeMessage wrappers from Meta AI / bots' do
      data = {
        'Info' => {
          'ID' => 'BOT-INVOKE-1',
          'Chat' => '867051314767696@bot',
          'IsFromMe' => false
        },
        'Message' => {
          'botInvokeMessage' => {
            'message' => {
              'richResponseMessage' => {
                'submessages' => [{ 'messageText' => 'Hi from bot' }]
              }
            }
          }
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:message][:richResponseMessage][:submessages].first[:messageText]).to eq('Hi from bot')
      expect(result[:message][:botInvokeMessage]).to be_nil
    end

    it 'maps fromMe payloads to the recipient peer JID' do
      data = {
        'Info' => {
          'ID' => 'MSG-FROM-ME',
          'Chat' => '556696971841@s.whatsapp.net',
          'Sender' => '5511999999999:38@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'RecipientAlt' => '556696971841@s.whatsapp.net',
          'IsFromMe' => true,
          'PushName' => 'Agent',
          'Timestamp' => 1_699_999_999
        },
        'Message' => {
          'conversation' => 'From phone'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:remoteJid]).to eq('556696971841@s.whatsapp.net')
      expect(result[:key][:remoteJidAlt]).to eq('556696971841@s.whatsapp.net')
      expect(result[:key][:fromMe]).to be(true)
    end

    it 'uses RecipientAlt for fromMe LID chats' do
      data = {
        'Info' => {
          'ID' => 'MSG-FROM-ME-LID',
          'Chat' => '123456789012345@lid',
          'Sender' => '5511999999999:38@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'RecipientAlt' => '556696971841@s.whatsapp.net',
          'IsFromMe' => true
        },
        'Message' => {
          'conversation' => 'From phone'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:remoteJid]).to eq('123456789012345@lid')
      expect(result[:key][:remoteJidAlt]).to eq('556696971841@s.whatsapp.net')
    end

    it 'prefers a phone alt over an @lid alt on inbound 1:1' do
      data = {
        'Info' => {
          'ID' => 'INBOUND-LID-ALT',
          'Chat' => '123456789012345@lid',
          'Sender' => '123456789012345@lid',
          'SenderAlt' => '123456789012345@lid',
          'RecipientAlt' => '556696971841@s.whatsapp.net',
          'IsFromMe' => false,
          'AddressingMode' => 'lid'
        },
        'Message' => {
          'conversation' => 'hello'
        }
      }

      result = described_class.canonicalize_data(data)

      aggregate_failures do
        expect(result[:key][:remoteJid]).to eq('123456789012345@lid')
        expect(result[:key][:remoteJidAlt]).to eq('556696971841@s.whatsapp.net')
      end
    end

    it 'omits remoteJidAlt for group chats and prefers SenderAlt as participant' do
      data = {
        'Info' => {
          'ID' => 'GROUP-LID-1',
          'Chat' => '120363012345678901@g.us',
          'Sender' => '123456789012345@lid',
          'SenderAlt' => '5511777777777@s.whatsapp.net',
          'IsFromMe' => false,
          'AddressingMode' => 'lid',
          'PushName' => 'Member'
        },
        'Message' => {
          'conversation' => 'Group hello'
        }
      }

      result = described_class.canonicalize_data(data)

      aggregate_failures do
        expect(result[:key][:remoteJid]).to eq('120363012345678901@g.us')
        expect(result[:key][:remoteJidAlt]).to be_nil
        expect(result[:key][:participant]).to eq('5511777777777@s.whatsapp.net')
        expect(result[:key][:addressingMode]).to eq('lid')
      end
    end

    it 'prefers SenderAlt over device Sender for group participants' do
      data = {
        'Info' => {
          'ID' => 'GROUP-DEVICE-1',
          'Chat' => '120363012345678901@g.us',
          'Sender' => '5511777777777:38@s.whatsapp.net',
          'SenderAlt' => '5511777777777@s.whatsapp.net',
          'IsFromMe' => false
        },
        'Message' => { 'conversation' => 'Hi' }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:participant]).to eq('5511777777777@s.whatsapp.net')
      expect(result[:key][:remoteJidAlt]).to be_nil
    end

    it 'returns empty hash for nil data' do
      expect(described_class.canonicalize_data(nil)).to eq({})
    end
  end
end
