require 'rails_helper'

RSpec.describe 'Service Session Reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:default_timezone) { ActiveSupport::TimeZone[0]&.name }
  let(:start_of_today) { Time.current.in_time_zone(default_timezone).beginning_of_day.to_i }
  let(:end_of_today) { Time.current.in_time_zone(default_timezone).end_of_day.to_i }

  describe 'GET /api/v2/accounts/:account_id/service_session_reports/summary' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/service_session_reports/summary"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          since: start_of_today.to_s,
          until: end_of_today.to_s,
          business_hours: true,
          inbox_id: '42'
        }
      end

      it 'returns unauthorized for agents' do
        get "/api/v2/accounts/#{account.id}/service_session_reports/summary",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'calls SummaryBuilder with symbolized params for admins' do
        summary_builder = instance_double(V2::Reports::ServiceSessions::SummaryBuilder)
        allow(V2::Reports::ServiceSessions::SummaryBuilder).to receive(:new).and_return(summary_builder)
        allow(summary_builder).to receive(:build).and_return(
          {
            open_sessions_count: 2,
            closed_sessions_count: 5,
            total_sessions: 7,
            avg_session_duration: 100.0,
            avg_first_response_time: 25.0,
            reopen_rate: 0.1,
            p95_first_response_time: 60,
            p95_session_resolution_time: 300,
            open_sessions_avg_age_seconds: 3600,
            open_sessions_p95_age_seconds: 7200,
            open_sessions_aging_buckets: { over_24h: 1, over_72h: 0, over_7d: 0 }
          }
        )

        get "/api/v2/accounts/#{account.id}/service_session_reports/summary",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::ServiceSessions::SummaryBuilder).to have_received(:new).with(
          account: account,
          params: hash_including(
            since: start_of_today.to_s,
            until: end_of_today.to_s,
            business_hours: true,
            inbox_id: '42'
          )
        )
        expect(summary_builder).to have_received(:build)
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['open_sessions_count']).to eq(2)
        expect(response.parsed_body['total_sessions']).to eq(7)
      end

      it 'returns unprocessable_entity when date range exceeds 6 months' do
        get "/api/v2/accounts/#{account.id}/service_session_reports/summary",
            params: { since: 1.year.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.date_range_too_long'))
      end

      it 'returns unprocessable_entity when since is after until' do
        get "/api/v2/accounts/#{account.id}/service_session_reports/summary",
            params: { since: end_of_today.to_s, until: start_of_today.to_s },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.invalid_date_range'))
      end
    end
  end
end
