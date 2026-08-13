class Api::V1::Accounts::ConversationWorkflowRulesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_rule, only: [:show, :update, :destroy, :activity]

  def index
    @rules = Current.account.conversation_workflow_rules.ordered
    skip_counts = ConversationWorkflowRuleSkip.recent_count_by_rule_ids(@rules.map(&:id))
    render json: @rules.map { |rule| rule_payload(rule, recent_skips_count: skip_counts[rule.id] || 0) }
  end

  def show
    render json: rule_payload(@rule)
  end

  def create
    @rule = Current.account.conversation_workflow_rules.new(rule_params)
    assign_position_on_create
    return render_legacy_conflict_error if legacy_conflict?(@rule)
    return render_could_not_create_error(@rule.errors.messages) unless @rule.save

    render json: rule_payload(@rule, include_legacy_warning: @rule.active?), status: :created
  end

  def update
    @rule.assign_attributes(rule_params)
    return render_legacy_conflict_error if legacy_conflict?(@rule)
    return render_could_not_create_error(@rule.errors.messages) unless @rule.save

    render json: rule_payload(@rule)
  end

  def destroy
    @rule.destroy!
    head :ok
  end

  def reorder
    Array(params[:rules]).each do |entry|
      rule = Current.account.conversation_workflow_rules.find_by(id: entry[:id])
      rule&.update!(position: entry[:position])
    end
    head :ok
  end

  def migrate_legacy
    Custom::ConversationWorkflow::MigrateLegacyService.new(Current.account).perform
    render json: { migrated: Current.account.reload.workflow_rules_migrated? }
  end

  def preview_count
    count = Custom::ConversationWorkflow::PreviewCountService.new(
      account: Current.account,
      attributes: preview_params
    ).perform
    render json: { count: count }
  rescue ArgumentError
    render json: { count: 0 }
  end

  # rubocop:disable Metrics/MethodLength -- executions + skips payload
  def activity
    executions = @rule.conversation_workflow_rule_executions
                      .includes(:conversation)
                      .order(executed_at: :desc)
                      .limit(10)
                      .map do |execution|
      {
        id: execution.id,
        conversation_id: execution.conversation_id,
        display_id: execution.conversation&.display_id,
        executed_at: execution.executed_at
      }
    end

    skips = @rule.conversation_workflow_rule_skips
                 .order(created_at: :desc)
                 .limit(10)
                 .map do |skip|
      {
        id: skip.id,
        action_name: skip.action_name,
        reason: skip.reason,
        metadata: skip.metadata,
        created_at: skip.created_at
      }
    end

    render json: { executions: executions, skips: skips }
  end
  # rubocop:enable Metrics/MethodLength

  private

  def fetch_rule
    @rule = Current.account.conversation_workflow_rules.find(params[:id])
  end

  def assign_position_on_create
    return if rule_params[:position].present?

    max_position = Current.account.conversation_workflow_rules.maximum(:position)
    @rule.position = max_position.to_i + 1
  end

  def rule_params
    permitted = params.permit(
      :name, :description, :active, :position, :trigger_type, :duration_minutes,
      :ignore_waiting, :resolve_on_match, :message,
      inbox_ids: [],
      options: [:require_no_first_reply, :respect_business_hours, { statuses: [] }],
      conditions: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }],
      actions: [:action_name, :counts_as_agent_reply, { action_params: [] }]
    )

    # MultiSelect may still send [{id, name}]; coerce to scalar ids.
    permitted[:inbox_ids] = normalize_id_list(params[:inbox_ids]) if params.key?(:inbox_ids)

    # action_params can be scalars OR nested hashes (send_email_to_team).
    # `action_params: []` only keeps scalars — reattach full params per action.
    permitted[:actions] = Array(params[:actions]).map { |action| sanitize_action(action) } if params[:actions].present?

    permitted
  end

  def normalize_id_list(values)
    return nil if values.blank?

    Array(values).filter_map do |value|
      # Integer/String respond to [] in Ruby — only coerce Hash/Parameters option shapes.
      if value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
        value[:id] || value['id']
      else
        value
      end
    end
  end

  def sanitize_action(action)
    action_hash = action.respond_to?(:to_unsafe_h) ? action.to_unsafe_h : action.to_h
    raw_counts = if action_hash.key?('counts_as_agent_reply')
                   action_hash['counts_as_agent_reply']
                 else
                   action_hash[:counts_as_agent_reply]
                 end

    {
      action_name: action_hash['action_name'] || action_hash[:action_name],
      counts_as_agent_reply: ActiveModel::Type::Boolean.new.cast(raw_counts),
      action_params: normalize_action_params(
        action_hash['action_params'] || action_hash[:action_params]
      )
    }
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- hash/array coercion
  def normalize_action_params(raw_params)
    return [] if raw_params.blank?

    if raw_params.is_a?(Hash) || raw_params.respond_to?(:permitted?)
      hash = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params
      # search_select often sends a single {id, name} object
      return [hash[:id] || hash['id']] if select_option_hash?(hash)

      return [hash.deep_stringify_keys]
    end

    Array(raw_params).map do |param|
      next param unless param.is_a?(Hash) || param.respond_to?(:permitted?)

      hash = param.respond_to?(:to_unsafe_h) ? param.to_unsafe_h : param
      next (hash[:id] || hash['id']) if select_option_hash?(hash)

      hash.deep_stringify_keys
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def select_option_hash?(hash)
    keys = hash.keys.map(&:to_s)
    keys.include?('id') && keys.include?('name') && keys.exclude?('team_ids')
  end

  def rule_payload(rule, include_legacy_warning: false, recent_skips_count: nil)
    payload = rule.as_json(
      only: %i[
        id account_id name description active position trigger_type duration_minutes inbox_ids
        ignore_waiting resolve_on_match message conditions actions options created_at updated_at
      ]
    )
    payload['legacy_auto_resolve_active'] = legacy_auto_resolve_active? if include_legacy_warning
    payload['recent_skips_count'] = recent_skips_count unless recent_skips_count.nil?
    payload
  end

  def legacy_auto_resolve_active?
    Current.account.auto_resolve_after.present? && !Current.account.workflow_rules_migrated?
  end

  def legacy_conflict?(rule)
    rule.active? && rule.conversation_inactivity? && legacy_auto_resolve_active?
  end

  def render_legacy_conflict_error
    render_could_not_create_error(
      base: ['Migrate legacy auto-resolve before activating inactivity workflow rules']
    )
  end

  def preview_params
    rule_params.to_h
  end
end
