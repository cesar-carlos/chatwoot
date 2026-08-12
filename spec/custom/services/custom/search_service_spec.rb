# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:team_member, user: agent, team: team)

    custom_role = create(:custom_role, account: account, permissions: %w[conversation_team_unassigned_manage])
    AccountUser.find_by(user: agent, account: account).update!(custom_role: custom_role)
  end

  it 'excludes messages from conversations outside the custom role scope' do
    mine = create(:conversation, account: account, inbox: inbox, assignee: agent)
    other = create(:conversation, account: account, inbox: inbox, assignee: other_agent)

    create(:message, account: account, inbox: inbox, conversation: mine, content: 'busca-mine-unique')
    create(:message, account: account, inbox: inbox, conversation: other, content: 'busca-other-unique')

    result = described_class.new(
      current_user: agent,
      current_account: account,
      search_type: 'Message',
      params: { q: 'busca' }
    ).perform

    contents = result[:messages].map(&:content)
    expect(contents).to include('busca-mine-unique')
    expect(contents).not_to include('busca-other-unique')
  end

  it 'falls back to plain ILIKE when unaccent SQL fails' do
    conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'plain search hit')

    allow(Custom::MessageSearch::Unaccent).to receive(:extension_enabled?).and_return(true)

    call_count = 0
    allow(Custom::MessageSearch::ContentPredicate).to receive(:sql) do |**kwargs|
      call_count += 1
      raise ActiveRecord::StatementInvalid, 'unaccent_immutable missing' if kwargs[:unaccent]

      '(messages.content ILIKE :pattern)'
    end

    result = described_class.new(
      current_user: agent,
      current_account: account,
      search_type: 'Message',
      params: { q: 'plain' }
    ).perform

    expect(result[:messages].map(&:content)).to include('plain search hit')
    expect(call_count).to be >= 2
  end
end
