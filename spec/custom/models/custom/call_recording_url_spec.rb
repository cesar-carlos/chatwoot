# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Call, '#recording_url' do
  let(:account) { create(:account) }
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
      meta: { 'record_url' => 'https://example.com/ext.ogg' }
    )
  end

  it 'falls back to meta record_url for wavoip calls' do
    expect(call.recording_url).to eq('https://example.com/ext.ogg')
  end
end
