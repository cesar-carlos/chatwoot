# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evolution Go contact sync API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => 'https://go.example.com',
        'global_api_key' => 'global-key',
        'instance_token' => 'instance-token',
        'instance_name' => 'test-go-instance',
        'instance_id' => 'inst-1',
        'webhook_token' => 'secret'
      )
    )
  end
  let(:inbox) { channel.inbox }

  describe 'POST /api/v1/accounts/:account_id/contacts/:id/evolution_go_sync' do
    it 'enqueues GroupMetadataFetchJob for WhatsApp group contacts' do
      group_jid = '120363012345678901@g.us'
      contact = create(
        :contact,
        account: account,
        phone_number: nil,
        identifier: group_jid,
        name: 'NortAgro Grupo (GROUP)',
        additional_attributes: {
          Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY => true,
          Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY => group_jid
        }
      )
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: group_jid)

      expect(Custom::Whatsapp::Evolution::GroupMetadataFetchJob).to receive(:perform_later)
        .with(channel.id, group_jid)
      expect(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).not_to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/evolution_go_sync",
           params: { inbox_id: inbox.id },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['message']).to eq('Contact sync started')
    end

    it 'enqueues ContactEnrichmentJob for 1:1 contacts' do
      contact = create(
        :contact,
        account: account,
        phone_number: '+5511999999999',
        additional_attributes: {
          'evolution_go_remote_jid' => '5511999999999@s.whatsapp.net'
        }
      )
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999')

      expect(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:perform_later)
        .with(
          channel.id,
          contact.id,
          hash_including(remote_jid: '5511999999999@s.whatsapp.net', force: true)
        )
      expect(Custom::Whatsapp::Evolution::GroupMetadataFetchJob).not_to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/evolution_go_sync",
           params: { inbox_id: inbox.id },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:accepted)
    end
  end
end
