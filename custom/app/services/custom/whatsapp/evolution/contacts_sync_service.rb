# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactsSyncService
  include Custom::Whatsapp::Evolution::Import::JidHelpers

  def initialize(channel:, data:)
    @channel = channel
    @inbox = channel.inbox
    @data = data
    @config = channel.provider_config || Custom::Whatsapp::Evolution::ProviderConfigDefaults::DEFAULTS
  end

  def perform
    Array.wrap(@data).each do |record|
      next unless record.is_a?(Hash)

      sync_record(record.with_indifferent_access)
    end
  end

  private

  attr_reader :channel, :inbox, :config

  def sync_record(record)
    remote_jid = record[:remoteJid].to_s
    return if skip_remote_jid?(remote_jid)

    phone = phone_from_contact_record(record)
    return if phone.blank?

    push_name = record[:pushName].to_s.strip.presence
    profile_pic_url = Custom::Whatsapp::Evolution::ContactEnrichmentService.profile_pic_url_from_record(record)
    contact = find_or_create_contact(phone, remote_jid, push_name)
    enqueue_enrichment(contact, remote_jid, push_name, profile_pic_url)
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(config)
  end

  def find_or_create_contact(phone, remote_jid, push_name)
    source_id = normalize_source_id(phone)
    contact_attributes = {
      name: push_name || "+#{phone}",
      phone_number: "+#{phone}",
      additional_attributes: { Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY => remote_jid }
    }
    contact_attributes[:identifier] = remote_jid if remote_jid.end_with?('@lid')

    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: source_id,
      contact_attributes: contact_attributes
    ).perform.contact
  end

  def enqueue_enrichment(contact, remote_jid, push_name, profile_pic_url)
    return unless Custom::Whatsapp::Evolution::ContactEnrichmentService.should_enqueue?(
      contact: contact,
      remote_jid: remote_jid,
      push_name: push_name,
      profile_pic_url: profile_pic_url
    )

    Custom::Whatsapp::Evolution::ContactEnrichmentJob.perform_later(
      channel.id,
      contact.id,
      {
        remote_jid: remote_jid,
        push_name: push_name,
        profile_pic_url: profile_pic_url
      }.compact
    )
  end
end
