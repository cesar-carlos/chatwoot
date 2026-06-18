require 'rails_helper'

RSpec.describe Custom::Conversations::ResolveService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  it 'resolves pending conversations directly' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending)

    described_class.new(conversation: conversation, skip_required_attributes: true).perform

    expect(conversation.reload.status).to eq('resolved')
  end

  it 'skips required attributes when flag set' do
    account.update!(settings: { 'conversation_required_attributes' => ['ticket_id'] })
    account.enable_features!(:conversation_required_attributes)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)

    expect do
      described_class.new(conversation: conversation, skip_required_attributes: true).perform
    end.not_to raise_error

    expect(conversation.reload.status).to eq('resolved')
  end
end
