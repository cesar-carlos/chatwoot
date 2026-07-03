# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::RemoteJidFilter do
  let(:config) do
    {
      'groups_ignore' => true,
      'ignore_status_broadcast' => true,
      'ignore_jids' => ['blocked@s.whatsapp.net']
    }
  end

  it 'skips blank remote jids' do
    expect(described_class.skip_remote_jid?('', config)).to be(true)
  end

  it 'skips status broadcast by default' do
    expect(described_class.skip_remote_jid?('status@broadcast', config)).to be(true)
  end

  it 'skips group jids when groups_ignore is enabled' do
    expect(described_class.skip_remote_jid?('120363@g.us', config)).to be(true)
  end

  it 'skips exact ignore_jids matches' do
    expect(described_class.skip_remote_jid?('blocked@s.whatsapp.net', config)).to be(true)
  end

  it 'allows direct contact jids when not ignored' do
    expect(described_class.skip_remote_jid?('5511999999999@s.whatsapp.net', config)).to be(false)
  end
end
