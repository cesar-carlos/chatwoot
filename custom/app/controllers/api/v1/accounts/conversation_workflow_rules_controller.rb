class Api::V1::Accounts::ConversationWorkflowRulesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_rule, only: [:show, :update, :destroy]

  def index
    @rules = Current.account.conversation_workflow_rules.ordered
    render json: @rules.map { |rule| rule_payload(rule) }
  end

  def show
    render json: rule_payload(@rule)
  end

  def create
    @rule = Current.account.conversation_workflow_rules.new(rule_params)
    assign_position_on_create
    return render_could_not_create_error(@rule.errors.messages) unless @rule.save

    render json: rule_payload(@rule, include_legacy_warning: @rule.active?), status: :created
  end

  def update
    @rule.assign_attributes(rule_params)
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
  end

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
    params.permit(
      :name, :description, :active, :position, :trigger_type, :duration_minutes,
      :ignore_waiting, :resolve_on_match, :message,
      inbox_ids: [],
      options: [:require_no_first_reply, :respect_business_hours, { statuses: [] }],
      conditions: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }],
      actions: [:action_name, :counts_as_agent_reply, { action_params: [] }]
    )
  end

  def rule_payload(rule, include_legacy_warning: false)
    payload = rule.as_json(
      only: %i[
        id account_id name description active position trigger_type duration_minutes inbox_ids
        ignore_waiting resolve_on_match message conditions actions options created_at updated_at
      ]
    )
    payload['legacy_auto_resolve_active'] = legacy_auto_resolve_active? if include_legacy_warning
    payload
  end

  def legacy_auto_resolve_active?
    Current.account.auto_resolve_after.present? && !Current.account.workflow_rules_migrated?
  end

  def preview_params
    rule_params.to_h
  end
end
