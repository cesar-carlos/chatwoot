# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- integration coverage for macro.name liquid
RSpec.describe 'Macros::ExecutionService liquid macro.name' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }
  let(:macro) do
    create(
      :macro,
      account: account,
      name: 'Follow up',
      actions: [{ 'action_name' => 'send_message', 'action_params' => ['From {{macro.name}}'] }]
    )
  end

  it 'interpolates macro.name when sending a message' do
    Macros::ExecutionService.new(macro, conversation, user).perform

    expect(conversation.messages.outgoing.last.content).to eq('From Follow up')
  ensure
    Current.reset
  end
end
# rubocop:enable RSpec/DescribeClass
