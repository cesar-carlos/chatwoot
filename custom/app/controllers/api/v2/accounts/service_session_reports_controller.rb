class Api::V2::Accounts::ServiceSessionReportsController < Api::V1::Accounts::BaseController
  MAX_ALLOWED_RANGE = 6.months

  before_action :check_authorization
  before_action :validate_date_range!
  before_action :prepare_builder_params

  def summary
    render_report_with(V2::Reports::ServiceSessions::SummaryBuilder)
  end

  def open
    render_report_with(V2::Reports::ServiceSessions::OpenSessionsBuilder)
  end

  def closed
    render_report_with(V2::Reports::ServiceSessions::ClosedSessionsBuilder)
  end

  def by_agent
    render_report_with(V2::Reports::ServiceSessions::AgentBuilder)
  end

  def by_inbox
    render_report_with(V2::Reports::ServiceSessions::InboxBuilder)
  end

  def by_team
    render_report_with(V2::Reports::ServiceSessions::TeamBuilder)
  end

  def by_label
    render_report_with(V2::Reports::ServiceSessions::LabelBuilder)
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def prepare_builder_params
    @builder_params = permitted_params.to_h
  end

  def render_report_with(builder_class)
    builder = builder_class.new(account: Current.account, params: @builder_params)
    render json: builder.build
  end

  def permitted_params
    params.permit(:since, :until, :business_hours, :inbox_id, :team_id, :user_ids, :label_ids, :page, :per_page)
  end

  def validate_date_range!
    return if permitted_params[:since].blank? || permitted_params[:until].blank?

    since_time = Time.zone.at(permitted_params[:since].to_i)
    until_time = Time.zone.at(permitted_params[:until].to_i)
    return unless (until_time - since_time) > MAX_ALLOWED_RANGE

    render_could_not_create_error(I18n.t('errors.reports.date_range_too_long'))
  end
end
