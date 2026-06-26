# FORK: Remove deprecated catalog entries and remap account bitmasks by feature name.
class ForkRemapFeatureFlagsAfterDeprecatedRemoval < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  OLD_FEATURE_NAMES = %w[
    inbound_emails channel_email channel_facebook conversation_unread_counts ip_lookup
    disable_branding email_continuity_on_api_channel help_center agent_bots macros
    agent_management team_management inbox_management labels custom_attributes automations
    canned_responses integrations voice_recorder report_rollup channel_website campaigns
    reports crm auto_resolve_conversations custom_reply_email custom_reply_domain audit_logs
    custom_tools channel_wavoip conversation_agent_no_reply_rules inbox_view sla
    help_center_embedding_search linear_integration captain_integration custom_roles
    chatwoot_v4 captain_v1_action_classifier contact_chatwoot_support_team shopify_integration
    search_with_gin channel_instagram crm_integration channel_voice notion_integration
    captain_integration_v2 whatsapp_embedded_signup whatsapp_campaign crm_v2 assignment_v2
    captain_document_auto_sync advanced_search saml advanced_search_indexing reply_mailer_migration
    quoted_email_reply companies channel_tiktok csat_review_notes captain_tasks
    conversation_required_attributes advanced_assignment
  ].freeze

  NEW_FEATURE_NAMES = OLD_FEATURE_NAMES - %w[whatsapp_embedded_signup quoted_email_reply]

  def up
    Account.find_each(batch_size: 100) do |account|
      enabled_by_name = decode_enabled_features(account.feature_flags, OLD_FEATURE_NAMES)
      new_flags = encode_feature_flags(enabled_by_name, NEW_FEATURE_NAMES)
      next if new_flags == account.feature_flags

      account.update_columns(feature_flags: new_flags, updated_at: Time.current)
    end

    cleanup_installation_defaults
  end

  private

  def decode_enabled_features(value, feature_names)
    feature_names.each_with_index.with_object({}) do |(name, index), result|
      result[name] = (value.to_i & (1 << index)).nonzero?
    end
  end

  def encode_feature_flags(enabled_by_name, feature_names)
    feature_names.each_with_index.sum do |name, index|
      enabled_by_name[name] ? (1 << index) : 0
    end
  end

  def cleanup_installation_defaults
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject do |feature|
      %w[whatsapp_embedded_signup quoted_email_reply].include?(feature['name'])
    end
    config.save!
    GlobalConfig.clear_cache
  end
end
