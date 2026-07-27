# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inboxes::HistoryMigration::CompatibilityGuard do
  let(:account) { create(:account) }
  let(:source_channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
  end
  let(:target_channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
  end
  let(:source) { source_channel.inbox }
  let(:target) { target_channel.inbox }

  describe '#validate!' do
    it 'passes for two WhatsApp inboxes in the same account' do
      expect do
        described_class.new(source: source, target: target).validate!
      end.not_to raise_error
    end

    it 'rejects the same inbox' do
      expect do
        described_class.new(source: source, target: source).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('same_inbox')
      }
    end

    it 'rejects inboxes from different accounts' do
      other = create(:channel_whatsapp, account: create(:account), sync_templates: false,
                                        validate_provider_config: false).inbox

      expect do
        described_class.new(source: source, target: other).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('different_accounts')
      }
    end

    it 'rejects non-WhatsApp destination' do
      email_inbox = create(:channel_email, account: account).inbox

      expect do
        described_class.new(source: source, target: email_inbox).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('incompatible_channels')
      }
    end

    it 'passes for two API inboxes in the same account' do
      api_source = create(:channel_api, account: account).inbox
      api_target = create(:channel_api, account: account).inbox

      expect do
        described_class.new(source: api_source, target: api_target).validate!
      end.not_to raise_error
    end

    it 'passes for API to WhatsApp' do
      api_source = create(:channel_api, account: account).inbox

      expect do
        described_class.new(source: api_source, target: target).validate!
      end.not_to raise_error
    end

    it 'passes for WhatsApp to API' do
      api_target = create(:channel_api, account: account).inbox

      expect do
        described_class.new(source: source, target: api_target).validate!
      end.not_to raise_error
    end

    it 'rejects API to Email' do
      api_source = create(:channel_api, account: account).inbox
      email_inbox = create(:channel_email, account: account).inbox

      expect do
        described_class.new(source: api_source, target: email_inbox).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('incompatible_channels')
      }
    end

    it 'rejects when a migration is already running' do
      InboxHistoryMigration.create!(
        account: account,
        source_inbox: source,
        target_inbox: target,
        status: 'running',
        started_at: Time.current,
        heartbeat_at: Time.current
      )

      expect do
        described_class.new(source: source, target: target).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('already_running')
      }
    end

    it 'rejects when a migration is still pending' do
      InboxHistoryMigration.create!(
        account: account,
        source_inbox: source,
        target_inbox: target,
        status: 'pending',
        created_at: Time.current
      )

      expect do
        described_class.new(source: source, target: target).validate!
      end.to raise_error(described_class::Error) { |error|
        expect(error.code).to eq('already_running')
      }
    end

    it 'allows a new migration after marking a stale running migration as failed' do
      stale = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source,
        target_inbox: target,
        status: 'running',
        started_at: 3.hours.ago,
        heartbeat_at: 3.hours.ago
      )

      expect do
        described_class.new(source: source, target: target).validate!
      end.not_to raise_error

      expect(stale.reload.status).to eq('failed')
      expect(stale.error_message).to include('Stale migration')
    end

    it 'allows a new migration after marking a stale pending migration as failed' do
      stale = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source,
        target_inbox: target,
        status: 'pending',
        created_at: 3.hours.ago
      )

      expect do
        described_class.new(source: source, target: target).validate!
      end.not_to raise_error

      expect(stale.reload.status).to eq('failed')
      expect(stale.error_message).to include('pending timed out')
    end
  end

  describe '.whatsapp_like?' do
    it 'is true for Channel::Whatsapp' do
      expect(described_class.whatsapp_like?(source)).to be(true)
    end

    it 'is true for Twilio WhatsApp' do
      twilio = create(:channel_twilio_sms, :whatsapp, account: account).inbox
      expect(described_class.whatsapp_like?(twilio)).to be(true)
    end

    it 'is false for email' do
      email_inbox = create(:channel_email, account: account).inbox
      expect(described_class.whatsapp_like?(email_inbox)).to be(false)
    end

    it 'is false for API' do
      api_inbox = create(:channel_api, account: account).inbox
      expect(described_class.whatsapp_like?(api_inbox)).to be(false)
    end
  end

  describe '.compatible?' do
    it 'is true for WhatsApp pairs' do
      expect(described_class.compatible?(source, target)).to be(true)
    end

    it 'is true for API pairs' do
      api_source = create(:channel_api, account: account).inbox
      api_target = create(:channel_api, account: account).inbox
      expect(described_class.compatible?(api_source, api_target)).to be(true)
    end

    it 'is true for mixed API and WhatsApp' do
      api_inbox = create(:channel_api, account: account).inbox
      expect(described_class.compatible?(source, api_inbox)).to be(true)
      expect(described_class.compatible?(api_inbox, source)).to be(true)
    end

    it 'is false for WhatsApp and Email' do
      email_inbox = create(:channel_email, account: account).inbox
      expect(described_class.compatible?(source, email_inbox)).to be(false)
    end
  end
end
