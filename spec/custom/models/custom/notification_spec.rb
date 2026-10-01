require 'rails_helper'

RSpec.describe Custom::Notification do
  it 'keeps event data compatible and localizes actions for the recipient' do
    notification = create(:notification)
    notification.user.update!(ui_settings: { locale: 'pt_BR' })
    data = notification.push_event_data
    expect(data).to include(id: notification.id, account_id: notification.account_id, user_id: notification.user_id)
    expect(data[:action_labels]).to eq(open: 'Abrir conversa', read: 'Marcar como lida')
    expect(data[:primary_actor]).to be_present
  end
end
