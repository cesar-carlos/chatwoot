# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::JidResolver < Custom::Whatsapp::Evolution::JidResolver
  # Addressing JID is what WhatsApp uses to deliver (raw @lid / @g.us). Phone JID
  # (resolve_message_jid) stays on the parent for wa_id / source_id / BR merge.
  def addressing_jid(key)
    key = key.with_indifferent_access
    remote = key[:remoteJid].to_s
    return remote if remote.end_with?('@lid') || group_jid?(remote)

    alt = key[:remoteJidAlt].to_s
    return alt if alt.end_with?('@lid')

    remote.presence
  end

  def self.merge_addressing_jid(stored, incoming)
    stored = stored.to_s
    incoming = incoming.to_s
    return incoming if stored.blank?
    return incoming if incoming.end_with?('@lid')
    return stored if stored.end_with?('@lid')

    incoming.presence || stored
  end
end
