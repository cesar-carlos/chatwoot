# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactEnrichmentService
  ENRICHMENT_COOLDOWN = 24.hours
  WHATSAPP_STATUS_KEY = 'whatsapp_status'
  WHATSAPP_BUSINESS_KEY = 'whatsapp_business'
  EVOLUTION_PUSH_NAME_KEY = 'evolution_push_name'
  EVOLUTION_REMOTE_JID_KEY = 'evolution_remote_jid'
  EVOLUTION_ENRICHED_AT_KEY = 'evolution_enriched_at'

  def self.profile_pic_url_from_record(record)
    return if record.blank?

    data = record.with_indifferent_access
    [
      data[:profilePicUrl],
      data[:profilePictureUrl],
      data[:profile_picture_url],
      data[:imgUrl],
      data.dig(:profilePicture, :url)
    ].map { |value| value.to_s.strip.presence }.compact.first
  end

  def self.should_enqueue?(contact:, remote_jid: nil, push_name: nil, profile_pic_url: nil, force: false)
    return true if ActiveModel::Type::Boolean.new.cast(force)

    additional = contact.additional_attributes.to_h.stringify_keys
    return true if remote_jid.to_s.present? && additional[EVOLUTION_REMOTE_JID_KEY] != remote_jid.to_s
    return true if profile_pic_url.to_s.present? && !contact.avatar.attached?
    return true if push_name_changed?(contact, push_name)

    enrichment_stale?(contact)
  end

  def self.enrichment_stale?(contact)
    enriched_at = contact.additional_attributes.to_h[EVOLUTION_ENRICHED_AT_KEY]
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
    previous_push_name = additional[EVOLUTION_PUSH_NAME_KEY].to_s.strip
    value != current_name && value != previous_push_name
  end

  def initialize(channel:, contact:, **options)
    @channel = channel
    @contact = contact
    @remote_jid = options[:remote_jid].to_s.presence
    @push_name = options[:push_name].to_s.strip.presence
    @profile_pic_url = options[:profile_pic_url].to_s.presence
    @force = ActiveModel::Type::Boolean.new.cast(options[:force])
  end

  def perform
    persist_remote_jid!
    update_name_from_push_name!
    sync_avatar_from_url(@profile_pic_url) if @profile_pic_url.present?

    if @force || profile_fetch_needed?
      mark_enriched! if fetch_and_apply_profile!
    elsif !contact.avatar.attached?
      fetch_profile_picture!(lookup_number)
    end
  end

  private

  attr_reader :channel, :contact, :force

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def lookup_number
    return @remote_jid if @remote_jid.to_s.include?('@')

    jid = contact.identifier.to_s
    return jid if jid.include?('@')

    contact.phone_number.to_s.gsub(/\D/, '').presence
  end

  def persist_remote_jid!
    return if @remote_jid.blank?

    updates = {}
    updates[:identifier] = @remote_jid if @remote_jid.end_with?('@lid') && contact.identifier != @remote_jid

    additional = contact.additional_attributes.stringify_keys
    return if additional[EVOLUTION_REMOTE_JID_KEY] == @remote_jid && updates.blank?

    additional[EVOLUTION_REMOTE_JID_KEY] = @remote_jid
    updates[:additional_attributes] = additional
    contact.update!(updates)
  end

  def update_name_from_push_name!
    return if @push_name.blank?
    return if contact.name == @push_name
    return unless name_updatable?

    additional = contact.additional_attributes.stringify_keys.merge(EVOLUTION_PUSH_NAME_KEY => @push_name)
    contact.update!(name: @push_name, additional_attributes: additional)
  end

  def name_updatable?
    return true if contact.name.blank?
    return true if contact_name_matches_phone?

    last_push = contact.additional_attributes[EVOLUTION_PUSH_NAME_KEY]
    contact.name == last_push
  end

  def contact_name_matches_phone?
    phone_number = contact.phone_number.to_s
    return false if phone_number.blank?

    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    contact.name == phone_number || contact.name == formatted_phone_number
  end

  def sync_avatar_from_url(url)
    return if url.blank? || contact.avatar.attached?

    ::Avatar::AvatarFromUrlJob.perform_later(contact, url)
  end

  def fetch_and_apply_profile!
    number = lookup_number
    return true if number.blank? # nothing to look up — not an error, no point retrying

    response = api_client.fetch_profile(number: number)
    return false unless response.success?

    apply_profile(response.parsed_response)
    fetch_profile_picture!(number) unless contact.avatar.attached?
    true
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION] contact enrichment failed for contact #{contact.id}: #{e.message}")
    false
  end

  def profile_fetch_needed?
    self.class.enrichment_stale?(contact)
  end

  def mark_enriched!
    additional = contact.additional_attributes.stringify_keys.merge(
      EVOLUTION_ENRICHED_AT_KEY => Time.current.utc.iso8601(3)
    )
    contact.update!(additional_attributes: additional)
  end

  def fetch_profile_picture!(number)
    response = api_client.fetch_profile_picture_url(number: number)
    return unless response.success?

    url = response.parsed_response['profilePictureUrl']
    sync_avatar_from_url(url) if url.present?
  end

  def apply_profile(profile)
    return if profile.blank?

    updates = {}
    custom = contact.custom_attributes.stringify_keys
    additional = contact.additional_attributes.stringify_keys

    apply_profile_name!(updates, additional, profile)
    apply_profile_status!(custom, profile)
    apply_business_profile!(updates, custom, additional, profile)
    apply_profile_identifier!(updates, profile)
    apply_profile_picture!(profile)

    updates[:custom_attributes] = custom if custom != contact.custom_attributes.stringify_keys
    updates[:additional_attributes] = additional if additional != contact.additional_attributes.stringify_keys
    contact.update!(updates) if updates.present?
  end

  def apply_profile_name!(updates, additional, profile)
    name = profile['name'].to_s.strip.presence
    return if name.blank? || contact.name == name
    return unless name_updatable?

    updates[:name] = name
    additional[EVOLUTION_PUSH_NAME_KEY] = name
  end

  def apply_profile_status!(custom, profile)
    status = profile['status'].to_s.presence
    custom[WHATSAPP_STATUS_KEY] = status if status.present?

    return unless profile.key?('isBusiness')

    custom[WHATSAPP_BUSINESS_KEY] = profile['isBusiness']
  end

  def apply_business_profile!(updates, custom, additional, profile)
    business = profile['businessProfile'] || profile['business']
    return if business.blank?

    apply_business_contact_fields!(updates, business)
    apply_business_custom_fields!(custom, business)
    apply_business_additional_fields!(additional, business)
  end

  def apply_business_contact_fields!(updates, business)
    updates[:email] = business['email'] if business['email'].present? && contact.email.blank?
  end

  def apply_business_custom_fields!(custom, business)
    custom['business_category'] = business['category'] if business['category'].present?
    custom['business_description'] = business['description'] if business['description'].present?
  end

  def apply_business_additional_fields!(additional, business)
    additional['city'] = business['address'] if business['address'].present? && additional['city'].blank?

    website = Array.wrap(business['website']).first
    additional['company_website'] = website if website.present?
  end

  def apply_profile_identifier!(updates, profile)
    wuid = profile['wuid'].presence || profile['wid'].presence
    return if wuid.blank? || !wuid.end_with?('@lid')
    return if contact.identifier == wuid

    updates[:identifier] = wuid
  end

  def apply_profile_picture!(profile)
    url = profile['profilePictureUrl'].to_s.presence
    sync_avatar_from_url(url) if url.present?
  end
end
