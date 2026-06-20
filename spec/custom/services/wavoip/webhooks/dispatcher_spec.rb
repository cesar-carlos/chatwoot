# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::Dispatcher do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  def dispatch_fixture(name)
    payload = JSON.parse(Rails.root.join("doc/feature/whatsapp-voice/wavoip-provider/fixtures/#{name}").read)
    described_class.new(inbox: inbox, payload: payload).dispatch
  end

  describe '#dispatch' do
    it 'routes CALL CREATE payloads to call upsert' do
      expect do
        dispatch_fixture('call_create_inbound_ring.json')
      end.to change(Call, :count).by(1)
    end

    it 'routes DEVICE payloads to device handler' do
      dispatch_fixture('call_create_inbound_ring.json')

      expect do
        dispatch_fixture('device_update.json')
      end.not_to change(Call, :count)

      expect(channel.reload.provider_config['device_status']).to eq('open')
    end

    it 'routes RECORD payloads to record handler' do
      call = create(
        :call,
        account: account,
        inbox: inbox,
        conversation: create(:conversation, account: account, inbox: inbox),
        contact: create(:contact, account: account),
        provider: :wavoip,
        provider_call_id: 'record_dispatch_001',
        direction: :incoming,
        status: 'completed'
      )
      record_payload = JSON.parse(file_fixture('wavoip/record_update.json').read)
      record_payload['whatsapp_call_id'] = call.provider_call_id

      expect do
        described_class.new(inbox: inbox, payload: record_payload).dispatch
      end.to have_enqueued_job(Wavoip::AttachRecordingJob).with(call.id, record_payload['record_url'])

      expect(call.reload.meta['record_url']).to eq(record_payload['record_url'])
    end
  end
end
