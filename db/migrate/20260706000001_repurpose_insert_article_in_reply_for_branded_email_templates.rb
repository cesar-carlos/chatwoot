class RepurposeInsertArticleInReplyForBrandedEmailTemplates < ActiveRecord::Migration[7.1]
  def up
    # FORK: insert_article_in_reply bit already remapped to conversation_agent_no_reply_rules.
    # branded_email_templates lives on feature_flags_ext_1 — do not clear the fork bit.
    if Account.respond_to?(:feature_branded_email_templates) &&
       Featurable::FEATURE_LIST.any? { |f| f['name'] == 'branded_email_templates' && f['column'].blank? }
      Account.feature_branded_email_templates.find_each(batch_size: 100) do |account|
        account.disable_features(:branded_email_templates)
        account.save!(validate: false)
      end
    end

    remove_stale_default_feature
  end

  private

  def remove_stale_default_feature
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |feature| feature['name'] == 'insert_article_in_reply' }
    config.save!
    GlobalConfig.clear_cache
  end
end
