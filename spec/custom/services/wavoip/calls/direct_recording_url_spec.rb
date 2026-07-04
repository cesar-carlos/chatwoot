# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::DirectRecordingUrl do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: create(:conversation, account: account, inbox: inbox),
      contact: create(:contact, account: account),
      provider: :wavoip,
      provider_call_id: 'DIRECT_URL_CALL_ID_001',
      direction: :incoming,
      status: 'completed'
    )
  end

  it 'builds the documented storage.wavoip.com URL from the provider call id' do
    expect(described_class.for(call)).to eq('https://storage.wavoip.com/DIRECT_URL_CALL_ID_001')
  end

  it 'returns nil when the call has no provider_call_id' do
    call.provider_call_id = nil

    expect(described_class.for(call)).to be_nil
  end
end
