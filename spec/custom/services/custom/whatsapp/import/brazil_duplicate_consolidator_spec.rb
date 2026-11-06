# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Import::BrazilDuplicateConsolidator do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:consolidator) { described_class.new(account: account, inbox: inbox) }

  it 'keeps the contact that already has a conversation and both source ids' do
    owner = create(:contact, account: account, phone_number: '+554399845097', name: 'Adelson Soeth')
    duplicate = create(:contact, account: account, phone_number: '+5543999845097', name: 'Adelson Ghizoni Soethe')
    legacy_link = create(:contact_inbox, contact: owner, inbox: inbox, source_id: '554399845097')
    create(:contact_inbox, contact: duplicate, inbox: inbox, source_id: '5543999845097')
    conversation = create(:conversation, account: account, inbox: inbox, contact: owner, contact_inbox: legacy_link)

    expect(consolidator.perform).to eq(1)

    expect(owner.reload.name).to eq('Adelson Soeth')
    expect(owner.phone_number).to eq('+554399845097')
    expect(account.contacts.find_by(id: duplicate.id)).to be_nil
    expect(inbox.contact_inboxes.where(contact_id: owner.id).pluck(:source_id)).to contain_exactly(
      '554399845097',
      '5543999845097'
    )
    expect(conversation.reload.contact_id).to eq(owner.id)
  end

  it 'keeps a real name when neither contact has a conversation' do
    named = create(:contact, account: account, phone_number: '+554399845098', name: 'Oficina')
    placeholder = create(:contact, account: account, phone_number: '+5543999845098', name: '+5543999845098')

    expect(consolidator.perform).to eq(1)

    expect(named.reload.name).to eq('Oficina')
    expect(account.contacts.find_by(id: placeholder.id)).to be_nil
  end

  it 'keeps the conversation contact and folds the duplicate profile into it' do
    owner = create(:contact, account: account, phone_number: '+554399845099', name: '+554399845099')
    duplicate = create(
      :contact,
      account: account,
      phone_number: '+5543999845099',
      name: 'Oficina',
      additional_attributes: { 'evolution_go_remote_jid' => '999@lid' }
    )
    owner.update!(additional_attributes: { 'evolution_go_remote_jid' => '554399845099@s.whatsapp.net' })
    duplicate.add_labels(['agenda'])
    legacy_link = create(:contact_inbox, contact: owner, inbox: inbox, source_id: '554399845099')
    conversation = create(:conversation, account: account, inbox: inbox, contact: owner, contact_inbox: legacy_link)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: owner)
    survey = create(
      :csat_survey_response,
      account: account,
      conversation: conversation,
      message: message,
      contact: duplicate,
      rating: 5
    )
    campaign = create(:campaign, account: account, inbox: inbox)
    recipient = CampaignRecipient.create!(account: account, campaign: campaign, contact: duplicate, inbox: inbox)

    expect(consolidator.perform).to eq(1)

    owner.reload
    expect(owner.name).to eq('Oficina')
    expect(owner.additional_attributes['evolution_go_remote_jid']).to eq('999@lid')
    expect(owner.label_list).to include('agenda')
    expect(survey.reload.contact_id).to eq(owner.id)
    expect(recipient.reload.contact_id).to eq(owner.id)
    expect(account.contacts.find_by(id: duplicate.id)).to be_nil
  end

  it 'does not merge contacts that already have different identifiers' do
    create(:contact, account: account, phone_number: '+554399845096', name: 'One', identifier: '111@lid')
    duplicate = create(
      :contact,
      account: account,
      phone_number: '+5543999845096',
      name: 'Two',
      identifier: '222@lid'
    )

    expect(consolidator.perform).to eq(0)
    expect(account.contacts.find_by(id: duplicate.id)).to be_present
  end

  it 'leaves numbers that are not Brazil mobile variants untouched' do
    first = create(:contact, account: account, phone_number: '+14155552671', name: 'One')
    second = create(:contact, account: account, phone_number: '+14155552672', name: 'Two')

    expect(consolidator.perform).to eq(0)

    expect(account.contacts.find_by(id: first.id)).to be_present
    expect(account.contacts.find_by(id: second.id)).to be_present
  end
end
