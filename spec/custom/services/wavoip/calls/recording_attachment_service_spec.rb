# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::RecordingAttachmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :outgoing,
      status: 'completed',
      accepted_by_agent_id: agent.id,
      provider_call_id: 'rec_001'
    )
  end
  let!(:message) do
    msg = Voice::CallMessageBuilder.new(call).perform!
    call.update!(message_id: msg.id)
    msg
  end
  let(:record_url) { 'https://example.com/recording.ogg' }

  it 'stores external url in meta when fetch fails' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('blocked'))

    described_class.new(call: call, record_url: record_url).perform

    expect(call.reload.meta['record_url']).to eq(record_url)
    expect(message.reload.content_attributes.dig('data', 'recording_url')).to eq(record_url)
  end

  it 'skips when call_recording_enabled is false' do
    channel.update!(provider_config: channel.provider_config.merge('call_recording_enabled' => false))

    expect(SafeFetch).not_to receive(:fetch)

    described_class.new(call: call, record_url: record_url).perform

    expect(call.reload.meta['record_url']).to be_nil
    expect(message.reload.content_attributes.dig('data', 'recording_url')).to be_nil
  end
end
