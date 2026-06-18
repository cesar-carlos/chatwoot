class V2::Reports::ServiceSessions::BaseBuilder
  include DateRangeHelper
  include V2::Reports::ServiceSessions::MetricsHelper

  CONVERSATION_LABEL_JOIN_SQL = <<~SQL.squish.freeze
    INNER JOIN taggings
      ON taggings.taggable_id = conversations.id
     AND taggings.taggable_type = 'Conversation'
     AND taggings.context = 'labels'
  SQL

  attr_reader :account, :params

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  def initialize(account:, params:)
    @account = account
    @params = params || {}
  end

  private

  def metric_column
    use_business_hours? ? :value_in_business_hours : :value
  end

  def use_business_hours?
    ActiveModel::Type::Boolean.new.cast(params[:business_hours])
  end

  def open_sessions_scope(apply_label_filter: true)
    scope = account.conversations.where(status: [:open, :pending])
    scope = apply_conversation_filters(scope, apply_label_filter: apply_label_filter)
    apply_open_date_filter(scope)
  end

  def closed_sessions_scope(apply_label_filter: true)
    scope = account.reporting_events.where(name: 'conversation_resolved')
    scope = apply_reporting_event_filters(scope, apply_label_filter: apply_label_filter)
    apply_closed_date_filter(scope)
  end

  def first_response_scope(apply_label_filter: true)
    scope = account.reporting_events.where(name: 'first_response')
    scope = apply_reporting_event_filters(scope, apply_label_filter: apply_label_filter)
    apply_closed_date_filter(scope)
  end

  def reopen_events_scope(apply_label_filter: true)
    scope = account.reporting_events.where(name: 'conversation_opened')
    scope = scope.where('reporting_events.value > 0')
    scope = apply_reporting_event_filters(scope, apply_label_filter: apply_label_filter)
    apply_closed_date_filter(scope)
  end

  def apply_conversation_filters(scope, apply_label_filter: true)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope = scope.where(team_id: team_id) if team_id.present?
    scope = scope.where(assignee_id: user_ids) if user_ids.present?
    return scope unless apply_label_filter

    apply_label_filter_to_conversations(scope)
  end

  def apply_reporting_event_filters(scope, apply_label_filter: true)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope = scope.joins(:conversation).where(conversations: { team_id: team_id }) if team_id.present?
    scope = scope.where(user_id: user_ids) if user_ids.present?
    return scope unless apply_label_filter

    apply_label_filter_to_reporting_events(scope)
  end

  def apply_label_filter_to_conversations(scope)
    return scope if label_ids.blank?

    scope
      .joins(CONVERSATION_LABEL_JOIN_SQL)
      .where(taggings: { tag_id: label_ids })
      .distinct
  end

  def apply_label_filter_to_reporting_events(scope)
    return scope if label_ids.blank?

    scope
      .joins(conversation: :taggings)
      .where(taggings: { taggable_type: 'Conversation', context: 'labels', tag_id: label_ids })
      .distinct
  end

  def apply_open_date_filter(scope)
    return scope if since_time.blank? && until_time.blank?

    # FORK: align open-session date filter with cycle start (conversation_opened), not last activity.
    scope = scope.joins(open_cycle_join_sql)
    session_time_sql = open_session_started_at_sql

    if since_time.present? && until_time.present?
      scope.where("#{session_time_sql} >= ? AND #{session_time_sql} <= ?", since_time, until_time)
    elsif since_time.present?
      scope.where("#{session_time_sql} >= ?", since_time)
    else
      scope.where("#{session_time_sql} <= ?", until_time)
    end
  end

  def apply_closed_date_filter(scope)
    return scope if since_time.blank? && until_time.blank?

    if since_time.present? && until_time.present?
      scope.where('reporting_events.event_end_time >= ? AND reporting_events.event_end_time <= ?', since_time, until_time)
    elsif since_time.present?
      scope.where('reporting_events.event_end_time >= ?', since_time)
    else
      scope.where('reporting_events.event_end_time <= ?', until_time)
    end
  end

  def since_time
    return @since_time if defined?(@since_time)

    @since_time = params[:since].present? ? parse_date_time(params[:since].to_s) : nil
  end

  def until_time
    return @until_time if defined?(@until_time)

    @until_time = params[:until].present? ? parse_date_time(params[:until].to_s) : nil
  end

  def inbox_id
    params[:inbox_id]
  end

  def team_id
    params[:team_id]
  end

  def user_ids
    @user_ids ||= normalize_ids(params[:user_ids])
  end

  def label_ids
    @label_ids ||= normalize_ids(params[:label_ids])
  end

  def normalize_ids(value)
    return [] if value.blank?

    Array(value)
      .flat_map { |item| item.to_s.split(',') }
      .map(&:strip)
      .reject(&:blank?)
      .map(&:to_i)
      .uniq
  end

  def page
    parsed_page = params[:page].to_i
    parsed_page.positive? ? parsed_page : DEFAULT_PAGE
  end

  def per_page
    parsed_per_page = params[:per_page].to_i
    return DEFAULT_PER_PAGE unless parsed_per_page.positive?

    [parsed_per_page, MAX_PER_PAGE].min
  end

  def paginate_scope(scope)
    scope.offset((page - 1) * per_page).limit(per_page)
  end

  def pagination_meta(total_count)
    {
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_count.zero? ? 0 : (total_count.to_f / per_page).ceil
    }
  end

  def serialize_resource(resource)
    return nil if resource.blank?

    {
      id: resource.id,
      name: resource.try(:name) || resource.try(:title)
    }
  end
end
