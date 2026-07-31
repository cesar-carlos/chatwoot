# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageReactionSyncService do
  before do
    allow_any_instance_of(Inbox).to receive(:create_default_working_hours) # rubocop:disable RSpec/AnyInstance
  end

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'react-sync-instance',
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:target) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'TARGETMSG1',
      content: 'Hello'
    )
  end

  def reaction_data(emoji: '👍', remove: false, from_me: false)
    {
      key: { id: 'TARGETMSG1', remoteJid: '5511999999999@s.whatsapp.net', fromMe: true },
      text: emoji,
      remove: remove,
      reaction_message_id: 'REACTION1',
      from_me: from_me,
      participant: nil
    }
  end

  it 'applies a reaction onto the target message content_attributes' do
    described_class.new(channel: channel, data: reaction_data).perform

    reactions = target.reload.content_attributes['reactions']
    expect(reactions.size).to eq(1)
    expect(reactions.first['emoji']).to eq('👍')
    expect(reactions.first['from']).to eq('contact')
    expect(reactions.first['target_message_id']).to eq('TARGETMSG1')
  end

  it 'replaces an existing reaction from the same actor' do
    described_class.new(channel: channel, data: reaction_data(emoji: '👍')).perform
    described_class.new(channel: channel, data: reaction_data(emoji: '❤️')).perform

    reactions = target.reload.content_attributes['reactions']
    expect(reactions.size).to eq(1)
    expect(reactions.first['emoji']).to eq('❤️')
  end

  it 'removes a reaction when remove is true' do
    described_class.new(channel: channel, data: reaction_data(emoji: '👍')).perform
    described_class.new(channel: channel, data: reaction_data(remove: true)).perform

    expect(target.reload.content_attributes['reactions']).to eq([])
  end

  it 'records skip stats when the target message is missing' do
    expect do
      described_class.new(
        channel: channel,
        data: reaction_data.merge(key: { id: 'MISSING', remoteJid: '5511999999999@s.whatsapp.net' })
      ).perform
    end.to change {
      channel.reload.provider_config.dig('mutation_stats', 'inbound_reaction_skipped').to_i
    }.by(1)
  end

  it 'uses user:self for fromMe reactions and replaces dashboard business reaction' do
    described_class.new(channel: channel, data: reaction_data(emoji: '👍', from_me: true)).perform
    expect(target.reload.content_attributes['reactions'].first['actor_key']).to eq('user:self')

    user = create(:user, account: account)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(
      instance_double(
        Custom::Whatsapp::EvolutionGo::ApiClient,
        react: instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: {})
      )
    )
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!)

    Custom::Whatsapp::EvolutionGo::ReactSyncService.new(
      message: target.reload,
      reaction: '❤️',
      user: user
    ).perform

    reactions = target.reload.content_attributes['reactions']
    expect(reactions.size).to eq(1)
    expect(reactions.first['emoji']).to eq('❤️')
    expect(reactions.first['actor_key']).to eq('user:self')
  end

  it 'sends group react with participant jid for inbound targets' do
    group_jid = '120363012345678901@g.us'
    contact = conversation.contact
    contact.update!(phone_number: nil, identifier: group_jid)
    conversation.contact_inbox.update!(source_id: group_jid)
    inbound = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'GROUPTARGET1',
      content: 'from member',
      content_attributes: {
        'evolution_go_remote_jid' => group_jid,
        'evolution_go_participant_jid' => '5511777777777@s.whatsapp.net'
      }
    )
    user = create(:user, account: account)
    api = instance_double(Custom::Whatsapp::EvolutionGo::ApiClient)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!)
    expect(api).to receive(:react).with(
      hash_including(
        number: group_jid,
        id: 'GROUPTARGET1',
        participant: '5511777777777@s.whatsapp.net'
      )
    ).and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: {}))

    Custom::Whatsapp::EvolutionGo::ReactSyncService.new(
      message: inbound,
      reaction: '👍',
      user: user
    ).perform
  end

  it 'sends group react with business jid when target is outgoing' do
    group_jid = '120363012345678901@g.us'
    channel.update!(
      phone_number: '+55000abcdef',
      provider_config: channel.provider_config.merge(
        'instance_name' => 'FORTEZA-FATURAMENTO-66996950396-1070BEFB08'
      )
    )
    contact = conversation.contact
    contact.update!(phone_number: nil, identifier: group_jid)
    conversation.contact_inbox.update!(source_id: group_jid)
    target.update!(
      content_attributes: { 'evolution_go_remote_jid' => group_jid }
    )
    user = create(:user, account: account)
    api = instance_double(Custom::Whatsapp::EvolutionGo::ApiClient)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!)
    expect(api).to receive(:react).with(
      hash_including(
        number: group_jid,
        id: 'TARGETMSG1',
        participant: '5566996950396@s.whatsapp.net',
        from_me: true
      )
    ).and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: {}))

    Custom::Whatsapp::EvolutionGo::ReactSyncService.new(
      message: target.reload,
      reaction: '👍',
      user: user
    ).perform
  end

  it 'bumps conversation last_activity_at' do
    conversation.update!(last_activity_at: 1.hour.ago)
    expect do
      described_class.new(channel: channel, data: reaction_data).perform
    end.to(change { conversation.reload.last_activity_at })
  end
end
