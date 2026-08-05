# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Conversations::OpenedByStamper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '.normalize' do
    it 'accepts contact, agent and phone' do
      expect(described_class.normalize('contact')).to eq('contact')
      expect(described_class.normalize('agent')).to eq('agent')
      expect(described_class.normalize('phone')).to eq('phone')
    end

    it 'rejects unknown values' do
      expect(described_class.normalize('system')).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe '.stamp!' do
    it 'persists opened_by on additional_attributes' do
      described_class.stamp!(conversation, described_class::CONTACT)

      expect(conversation.reload.additional_attributes['opened_by']).to eq('contact')
    end

    it 'ignores invalid values' do
      described_class.stamp!(conversation, 'invalid')

      expect(conversation.reload.additional_attributes['opened_by']).to be_nil
    end
  end

  describe '.merge_create_params' do
    it 'merges Current.conversation_opened_by into additional_attributes' do
      Current.conversation_opened_by = described_class::AGENT
      params = described_class.merge_create_params(account_id: account.id, additional_attributes: {})

      expect(params[:additional_attributes]['opened_by']).to eq('agent')
    ensure
      Current.reset
    end

    it 'keeps an explicit opened_by on params' do
      params = described_class.merge_create_params(
        account_id: account.id,
        additional_attributes: { 'opened_by' => 'phone' }
      )

      expect(params[:additional_attributes]['opened_by']).to eq('phone')
    end
  end
end
