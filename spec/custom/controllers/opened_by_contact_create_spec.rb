# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'opened_by contact create paths', type: :request do
  describe 'POST /api/v1/widget/conversations' do
    let(:account) { create(:account) }
    let(:web_widget) { create(:channel_widget, account: account) }
    let(:contact) { create(:contact, account: account, email: nil) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
    let(:token) do
      Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
    end

    it 'stamps opened_by=contact when the contact starts the conversation' do
      post '/api/v1/widget/conversations',
           headers: { 'X-Auth-Token' => token },
           params: {
             website_token: web_widget.website_token,
             contact: { name: 'contact-name' },
             message: { content: 'oi' }
           },
           as: :json

      expect(response).to have_http_status(:success)
      conversation = web_widget.inbox.conversations.find_by!(display_id: response.parsed_body['id'])
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
      expect(conversation.additional_attributes['browser']).to be_present
    end
  end

  describe 'POST /public/api/v1/inboxes/:identifier/contacts/:source_id/conversations' do
    let(:api_channel) { create(:channel_api) }
    let(:contact) { create(:contact, account: api_channel.account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_channel.inbox) }

    it 'stamps opened_by=contact and ignores client additional_attributes' do
      post "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{contact_inbox.source_id}/conversations",
           params: { additional_attributes: { 'opened_by' => 'agent' }, custom_attributes: { 'order' => '1' } }

      expect(response).to have_http_status(:success)
      conversation = api_channel.inbox.conversations.find_by!(display_id: response.parsed_body['id'])
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
      expect(conversation.custom_attributes).to eq('order' => '1')
      expect(Current.conversation_opened_by).to be_nil
    end
  end
end
