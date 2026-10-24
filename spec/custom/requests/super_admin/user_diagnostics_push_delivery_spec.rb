require 'rails_helper'

RSpec.describe 'Super Admin push delivery columns', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:user) { create(:user, email: 'agent@example.com') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'shows the provider, last sync and last delivery without the endpoint' do
    synced_at = Time.zone.parse('2026-10-20 09:30:00')
    pushed_at = Time.zone.parse('2026-10-21 10:15:00')
    user.notification_subscriptions.create!(
      subscription_type: 'browser_push',
      identifier: 'https://fcm.googleapis.com/wp/SECRETTOKEN',
      subscription_attributes: { 'endpoint' => 'https://fcm.googleapis.com/wp/SECRETTOKEN' },
      last_synced_at: synced_at,
      last_push_at: pushed_at,
      last_push_status: 'failed',
      last_push_error: 'error_class=WebPush::Unauthorized http_status=403 provider_reason=BadJwtToken'
    )
    user.notification_subscriptions.create!(
      subscription_type: 'fcm',
      identifier: 'phone-token',
      subscription_attributes: { 'device_id' => 'DEVICE-ABC', 'push_token' => 'phone-token' }
    )

    get '/super_admin/user_diagnostics', params: { user_query: user.email, tab: 'push' }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      'Provider', 'Last device sync', 'Last delivery', 'google',
      '2026-10-20 09:30', 'Failed', '2026-10-21 10:15', 'provider_reason=BadJwtToken'
    )
    expect(response.body).not_to include('SECRETTOKEN')
  end
end
