# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Settings', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/settings' do
    context 'when self-hosted enterprise with users over license limit' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
        allow(ChatwootHub).to receive(:pricing_plan).and_return('premium')
        allow(ChatwootHub).to receive(:pricing_plan_quantity).and_return(1)
        create_list(:user, 3)
        sign_in(super_admin, scope: :super_admin)
      end

      it 'does not show license banner' do
        get super_admin_settings_path
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Please add more licenses')
      end
    end

    context 'when cloud with users over license limit' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
        allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
        allow(ChatwootHub).to receive(:pricing_plan).and_return('premium')
        allow(ChatwootHub).to receive(:pricing_plan_quantity).and_return(1)
        create_list(:user, 3)
        sign_in(super_admin, scope: :super_admin)
      end

      it 'shows license banner' do
        get super_admin_settings_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Please add more licenses')
      end
    end
  end
end
