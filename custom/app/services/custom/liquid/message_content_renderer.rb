# frozen_string_literal: true

# Renders Liquid message templates with the same drops as Message#Liquidable,
# plus rule/macro when Current.executed_by (or an explicit override) is present.
class Custom::Liquid::MessageContentRenderer
  def self.render(template, conversation:, executed_by: Current.executed_by)
    new(template: template, conversation: conversation, executed_by: executed_by).render
  end

  def initialize(template:, conversation:, executed_by: nil)
    @template = template
    @conversation = conversation
    @executed_by = executed_by
  end

  def render
    return '' if @template.blank?
    return @template.to_s if @conversation.blank?

    Liquid::Template.parse(@template.to_s).render(message_drops)
  rescue Liquid::Error
    @template.to_s
  end

  private

  def message_drops
    drops = {
      'contact' => ContactDrop.new(@conversation.contact),
      'agent' => UserDrop.new(@conversation.assignee),
      'conversation' => ConversationDrop.new(@conversation),
      'inbox' => InboxDrop.new(@conversation.inbox),
      'account' => AccountDrop.new(@conversation.account)
    }
    merge_executed_by_drop(drops)
  end

  def merge_executed_by_drop(drops)
    case @executed_by
    when AutomationRule, ConversationWorkflowRule
      drops.merge('rule' => AutomationRuleDrop.new(@executed_by))
    when Macro
      drops.merge('macro' => MacroDrop.new(@executed_by))
    else
      drops
    end
  end
end
