# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Import::ContactLocator do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end

  def locator(merge_brazil:)
    described_class.new(account: account, inbox: inbox, merge_brazil: merge_brazil)
  end

  it 'returns the inbox owner of the canonical source id ahead of the contact stored with the 9' do
    owner = create(:contact, account: account, phone_number: '+554399845097', name: 'Adelson Soeth')
    create(:contact_inbox, contact: owner, inbox: inbox, source_id: '5543999845097')
    create(:contact, account: account, phone_number: '+5543999845097', name: 'Adelson Ghizoni Soethe')

    expect(locator(merge_brazil: true).find('5543999845097')).to eq(owner)
  end

  it 'prefers the contact whose inbox link already has a conversation' do
    owner = create(:contact, account: account, phone_number: '+554399845097', name: 'Adelson Soeth')
    legacy_link = create(:contact_inbox, contact: owner, inbox: inbox, source_id: '554399845097')
    create(:conversation, account: account, inbox: inbox, contact: owner, contact_inbox: legacy_link)
    other = create(:contact, account: account, phone_number: '+5543999845097', name: 'Adelson Ghizoni Soethe')
    create(:contact_inbox, contact: other, inbox: inbox, source_id: '5543999845097')

    expect(locator(merge_brazil: true).find('5543999845097')).to eq(owner)
  end

  it 'does not cross Brazil variants when merge is off' do
    owner = create(:contact, account: account, phone_number: '+554399845097', name: 'Adelson Soeth')
    create(:contact_inbox, contact: owner, inbox: inbox, source_id: '554399845097')

    expect(locator(merge_brazil: false).find('5543999845097')).to be_nil
  end
end
