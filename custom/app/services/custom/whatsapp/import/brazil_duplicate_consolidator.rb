# frozen_string_literal: true

# Folds Brazil mobile numbers stored with and without the extra 9 into one contact.
# The contact that already has conversations in this inbox stays.
class Custom::Whatsapp::Import::BrazilDuplicateConsolidator
  ADDRESSING_KEYS = %w[evolution_go_remote_jid evolution_remote_jid].freeze

  pattr_initialize [:account!, :inbox!]

  def perform
    merged = 0
    duplicate_groups.each do |ids|
      contacts = account.contacts.where(id: ids).to_a
      next if contacts.size < 2

      merged += merge_group(contacts)
    end
    merged
  end

  private

  def merge_group(contacts)
    keeper = choose_keeper(contacts)
    merged = 0
    contacts.each do |contact|
      next if contact.id == keeper.id
      next unless merge_into_keeper!(keeper, contact)

      keeper.reload
      merged += 1
    end
    merged
  end

  def duplicate_groups
    normalizer = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new
    groups = Hash.new { |hash, key| hash[key] = [] }
    brazil_phone_rows.each do |contact_id, phone_number|
      canonical = normalizer.normalize(phone_number.to_s.delete_prefix('+'))
      next if normalizer.variants(canonical).one?

      groups[canonical] << contact_id
    end
    groups.values.select(&:many?)
  end

  def brazil_phone_rows
    account.contacts.where("phone_number LIKE '+55%'").pluck(:id, :phone_number)
  end

  def choose_keeper(contacts)
    ids = contacts.map(&:id)
    inbox_counts = conversation_counts(ids, inbox_id: inbox.id)
    account_counts = conversation_counts(ids)

    contacts.max_by do |contact|
      [
        inbox_counts[contact.id].to_i,
        account_counts[contact.id].to_i,
        placeholder_name?(contact) ? 0 : 1,
        -contact.created_at.to_f
      ]
    end
  end

  def conversation_counts(contact_ids, inbox_id: nil)
    scope = Conversation.where(account_id: account.id, contact_id: contact_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope.group(:contact_id).count
  end

  def placeholder_name?(contact)
    name = contact.name.to_s
    return true if name.blank?

    phone_number = contact.phone_number.to_s
    return true if name == phone_number

    name == TelephoneNumber.parse(phone_number).international_number
  end

  def merge_into_keeper!(keeper, contact)
    return false unless account.contacts.exists?(contact.id)
    return false if conflicting_identifiers?(keeper, contact)

    labels = contact.label_list.to_a
    ActiveRecord::Base.transaction do
      preserve_keeper_identity!(keeper, contact)
      move_related_records!(keeper, contact)
      ContactMergeAction.new(account: account, base_contact: keeper, mergee_contact: contact).perform
      copy_labels!(keeper, labels)
    end
    true
  rescue ActiveRecord::ActiveRecordError => e
    log_skipped_merge(keeper, contact, e.message)
    false
  end

  def conflicting_identifiers?(keeper, contact)
    left = keeper.identifier.to_s
    right = contact.identifier.to_s
    return false if left.blank? || right.blank? || left == right

    log_skipped_merge(keeper, contact, 'different identifiers')
    true
  end

  def preserve_keeper_identity!(keeper, mergee)
    attributes = keeper.additional_attributes.to_h.stringify_keys
    mergee_attributes = mergee.additional_attributes.to_h.stringify_keys
    ADDRESSING_KEYS.each do |key|
      merged = Custom::Whatsapp::EvolutionGo::JidResolver.merge_addressing_jid(attributes[key], mergee_attributes[key])
      attributes[key] = merged if merged.to_s.end_with?('@lid')
    end
    keeper.additional_attributes = attributes
    keeper.name = mergee.name if placeholder_name?(keeper) && !placeholder_name?(mergee)
    keeper.save! if keeper.changed?
  end

  def move_related_records!(keeper, mergee)
    move_survey_responses!(keeper, mergee)
    move_campaign_recipients!(keeper, mergee)
  end

  def move_survey_responses!(keeper, mergee)
    CsatSurveyResponse.where(account_id: account.id, contact_id: mergee.id).find_each do |response|
      response.update!(contact_id: keeper.id)
    end
  end

  def move_campaign_recipients!(keeper, mergee)
    return unless defined?(CampaignRecipient)

    CampaignRecipient.where(account_id: account.id, contact_id: mergee.id).find_each do |recipient|
      move_campaign_recipient!(keeper, recipient)
    end
  end

  def move_campaign_recipient!(keeper, recipient)
    if CampaignRecipient.exists?(campaign_id: recipient.campaign_id, contact_id: keeper.id)
      recipient.destroy!
    else
      recipient.update!(contact_id: keeper.id)
    end
  end

  def copy_labels!(keeper, labels)
    keeper.reload
    extra = labels - keeper.label_list
    keeper.add_labels(extra) if extra.present?
  end

  def log_skipped_merge(keeper, contact, reason)
    Rails.logger.warn(
      '[WHATSAPP_IMPORT] skipped Brazil contact merge ' \
      "account=#{account.id} base=#{keeper.id} mergee=#{contact.id}: #{reason}"
    )
  end
end
