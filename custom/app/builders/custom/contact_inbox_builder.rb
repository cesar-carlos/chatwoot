# frozen_string_literal: true

module Custom::ContactInboxBuilder
  private

  def generate_source_id
    return wavoip_source_id if wavoip_inbox?

    super
  end

  def wavoip_source_id
    raise ActionController::ParameterMissing, 'contact phone number' unless @contact.phone_number

    @contact.phone_number.delete('+').to_s
  end

  def update_old_contact_inbox
    # Channel::Whatsapp rejects the Twilio-style source_id the upstream steal writes.
    # Rewriting it would also detach the contact that already receives this number.
    raise ActiveRecord::RecordNotUnique if @inbox.whatsapp?

    super
  end

  def allowed_channels?
    super || wavoip_inbox?
  end

  def wavoip_inbox?
    @inbox.channel_type == 'Channel::Wavoip'
  end
end
