# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ContactEnrichmentService
  ENRICHMENT_COOLDOWN = 24.hours
  WHATSAPP_STATUS_KEY = 'whatsapp_status'
  EVOLUTION_GO_PUSH_NAME_KEY = 'evolution_go_push_name'
  EVOLUTION_GO_REMOTE_JID_KEY = 'evolution_go_remote_jid'
  EVOLUTION_GO_ENRICHED_AT_KEY = 'evolution_go_enriched_at'

  def self.should_enqueue?(contact:, remote_jid: nil, push_name: nil, force: false)
    return true if ActiveModel::Type::Boolean.new.cast(force)

    additional = contact.additional_attributes.to_h.stringify_keys
    return true if remote_jid.to_s.present? && additional[EVOLUTION_GO_REMOTE_JID_KEY] != remote_jid.to_s
    return true if !contact.avatar.attached?
    return true if push_name_changed?(contact, push_name)

    enrichment_stale?(contact)
  end

  def self.enrichment_stale?(contact)
    enriched_at = contact.additional_attributes.to_h[EVOLUTION_GO_ENRICHED_AT_KEY]
    return true if enriched_at.blank?

    Time.zone.parse(enriched_at) <= ENRICHMENT_COOLDOWN.ago
  rescue ArgumentError
    true
  end

  def self.push_name_changed?(contact, push_name)
    value = push_name.to_s.strip
    return false if value.blank?

    additional = contact.additional_attributes.to_h.stringify_keys
    current_name = contact.name.to_s.strip
    previous_push_name = additional[EVOLUTION_GO_PUSH_NAME_KEY].to_s.strip
    value != current_name && value != previous_push_name
  end

  def initialize(channel:, contact:, **options)
    @channel = channel
    @contact = contact
    @remote_jid = options[:remote_jid].to_s.presence
    @push_name = options[:push_name].to_s.strip.presence
    @force = ActiveModel::Type::Boolean.new.cast(options[:force])
  end

  def perform
    persist_remote_jid!
    update_name_from_push_name!
    fetch_and_apply_profile!
    mark_enriched!
  end

  private

  attr_reader :channel, :contact

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def lookup_jid
    return @remote_jid if @remote_jid.to_s.include?('@')

    phone = contact.phone_number.to_s.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end

  def lookup_number
    lookup_jid&.split('@')&.first || contact.phone_number.to_s.gsub(/\D/, '')
  end

  def persist_remote_jid!
    return if @remote_jid.blank?

    updates = {}
    updates[:identifier] = @remote_jid if @remote_jid.end_with?('@lid') && contact.identifier != @remote_jid

    additional = contact.additional_attributes.stringify_keys
    return if additional[EVOLUTION_GO_REMOTE_JID_KEY] == @remote_jid && updates.blank?

    additional[EVOLUTION_GO_REMOTE_JID_KEY] = @remote_jid
    updates[:additional_attributes] = additional
    contact.update!(updates)
  end

  def update_name_from_push_name!
    return if @push_name.blank?
    return if contact.name == @push_name
    return unless name_updatable?

    additional = contact.additional_attributes.stringify_keys.merge(EVOLUTION_GO_PUSH_NAME_KEY => @push_name)
    contact.update!(name: @push_name, additional_attributes: additional)
  end

  def name_updatable?
    return true if contact.name.blank?
    return true if contact_name_matches_phone?

    last_push = contact.additional_attributes[EVOLUTION_GO_PUSH_NAME_KEY]
    contact.name == last_push
  end

  def contact_name_matches_phone?
    phone_number = contact.phone_number.to_s
    return false if phone_number.blank?

    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    contact.name == phone_number || contact.name == formatted_phone_number
  end

  def fetch_and_apply_profile!
    jid = lookup_jid
    number = lookup_number
    return true if jid.blank? && number.blank?
    return false unless whatsapp_user_exists?(number)

    applied = false
    applied = apply_user_info!(jid) if jid.present?
    applied = fetch_and_apply_avatar!(number) || applied
    applied
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] contact enrichment failed for contact #{contact.id}: #{e.message}")
    false
  end

  def apply_user_info!(jid)
    response = api_client.user_info(numbers: [jid])
    return false unless response.success?

    profile = extract_user_profile(response.parsed_response, jid)
    return false if profile.blank?

    apply_profile(profile, jid)
    true
  end

  def extract_user_profile(parsed, jid)
    data = parsed.is_a?(Hash) ? (parsed['data'] || parsed) : {}
    users = data['Users'] || data['users'] || {}
    users[jid] || users[jid.to_s] || users.values.first
  end

  def apply_profile(profile, jid)
    return if profile.blank?

    updates = {}
    additional = contact.additional_attributes.stringify_keys
    name = profile['VerifiedName'].to_s.strip.presence
    if name.present? && name_updatable? && contact.name != name
      updates[:name] = name
      additional[EVOLUTION_GO_PUSH_NAME_KEY] = name
    end

    status = profile['Status'].to_s.presence
    if status.present?
      custom = contact.custom_attributes.stringify_keys
      custom[WHATSAPP_STATUS_KEY] = status
      updates[:custom_attributes] = custom
    end

    lid = profile['LID'].to_s.presence
    updates[:identifier] = lid if lid.present? && lid.end_with?('@lid') && contact.identifier != lid

    additional[EVOLUTION_GO_REMOTE_JID_KEY] ||= jid
    updates[:additional_attributes] = additional if additional != contact.additional_attributes.stringify_keys
    contact.update!(updates) if updates.present?
  end

  def fetch_and_apply_avatar!(number)
    return false if number.blank? || contact.avatar.attached?

    response = api_client.user_avatar(number: number, preview: false)
    return false unless response.success?

    parsed = response.parsed_response
    base64 = parsed['avatar'] || parsed.dig('data', 'avatar')
    return false if base64.blank?

    Custom::Avatar::AvatarFromBase64Job.perform_later(contact, base64)
    true
  end

  def mark_enriched!
    additional = contact.additional_attributes.stringify_keys.merge(
      EVOLUTION_GO_ENRICHED_AT_KEY => Time.current.utc.iso8601(3)
    )
    contact.update!(additional_attributes: additional)
    true
  end

  def whatsapp_user_exists?(number)
    return true if number.blank?

    response = api_client.user_check(number: number)
    return true unless response.success?

    parsed = response.parsed_response
    data = parsed.is_a?(Hash) ? (parsed['data'] || parsed) : {}
    exists = data['exists']
    return exists if exists.in?([true, false])

    ActiveModel::Type::Boolean.new.cast(data['Exists'])
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] user/check failed for contact #{contact.id}: #{e.message}")
    true
  end
end
