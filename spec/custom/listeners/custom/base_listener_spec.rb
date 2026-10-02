require 'rails_helper'

RSpec.describe BaseListener do
  let(:listener) { described_class.instance }
  let(:conversation) { create(:conversation) }

  it 'omits the internal ledger from webhook changes without mutating the asynchronous assignment event' do
    state = { 'revision' => 'assignment-revision', 'delivered_user_ids' => [23] }
    attributes = { 'conversation_language' => 'pt', 'team_notification_transition' => state }
    event = Events::Base.new('conversation.updated', Time.current, conversation: conversation,
                                                                   changed_attributes: { 'additional_attributes' => [nil, attributes] })
    expect(listener.extract_changed_attributes(event)).to eq(
      [{ 'additional_attributes' => { previous_value: nil, current_value: { 'conversation_language' => 'pt' } } }]
    )
    expect(event.data[:changed_attributes]['additional_attributes'].last).to eq(attributes)
    expect(Custom::Notification::TeamAssignmentTransition.event_revision(event)).to eq(state['revision'])
  end

  it 'does not alter unrelated contact attributes with the same key or an event without changes' do
    contact = conversation.contact
    changes = { 'additional_attributes' => [{}, { 'team_notification_transition' => 'contact attribute' }] }
    event = Events::Base.new('contact.updated', Time.current, contact: contact, changed_attributes: changes)
    expect(listener.extract_changed_attributes(event).first['additional_attributes'][:current_value]).to eq(changes['additional_attributes'].last)
    empty = Events::Base.new('conversation.created', Time.current, conversation: conversation)
    expect(listener.extract_changed_attributes(empty)).to be_nil
  end
end
