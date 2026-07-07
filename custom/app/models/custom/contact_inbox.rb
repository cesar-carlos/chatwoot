# frozen_string_literal: true

module Custom::ContactInbox
  private

  def validate_whatsapp_source_id
    return if evolution_group_source_id?

    super
  end

  def evolution_group_source_id?
    inbox.channel_type == 'Channel::Whatsapp' &&
      inbox.channel.provider.in?(%w[evolution evolution_go]) &&
      Custom::Whatsapp::Evolution::GroupContactService.group_jid?(source_id)
  end
end

ContactInbox.prepend_mod_with('ContactInbox')
