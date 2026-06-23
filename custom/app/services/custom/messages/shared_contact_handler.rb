class Custom::Messages::SharedContactHandler
  def initialize(account:, conversation:, params:, attachments:, user: nil)
    @account = account
    @conversation = conversation
    @params = params
    @attachments = attachments
    @user = user
  end

  def attach_to(message)
    contact_id = extract_shared_contact_id
    return if contact_id.blank?

    validate!
    contact = find_contact(contact_id)
    authorize_contact!(contact)
    build_attachment(message, contact)
  end

  private

  def validate!
    raise StandardError, 'Cannot mix shared contact with file attachments' if @attachments.present?
    raise StandardError, 'Cannot send shared contact with message content' if shared_contact_content_present?
    raise StandardError, 'Cannot send shared contact as private note' if shared_contact_private?
    raise StandardError, 'Channel does not support contact sharing' unless channel_supported?
  end

  def shared_contact_content_present?
    @params[:content].present?
  end

  def shared_contact_private?
    ActiveModel::Type::Boolean.new.cast(@params[:private])
  end

  def channel_supported?
    channel = @conversation.inbox&.channel
    channel.present? && ChannelCapabilities::ShareContact.supports?(channel)
  end

  def find_contact(contact_id)
    contact = @account.contacts.find_by(id: contact_id)
    raise StandardError, 'Contact not found' if contact.blank?
    raise StandardError, 'Contact phone number required' if contact.phone_number.blank?

    contact
  end

  def authorize_contact!(_contact)
    return if @user.blank?

    account_user = AccountUser.find_by(user: @user, account: @account)
    raise StandardError, 'Not authorized to share this contact' unless can_share_contact?(account_user)
  end

  def can_share_contact?(account_user)
    return false if account_user.blank?

    permissions = account_user.permissions.map(&:to_s)
    return true if permissions.intersect?(%w[administrator agent])
    return true if permissions.include?('contact_manage')

    false
  end

  def build_attachment(message, contact)
    first_name, last_name = split_contact_name(contact.name)
    phone = normalized_share_phone(contact.phone_number)
    meta = { firstName: first_name, lastName: last_name, companyName: contact_company_name(contact) }.compact

    message.attachments.build(
      account_id: @account.id,
      file_type: :contact,
      fallback_title: phone,
      meta: meta
    )
  end

  def contact_company_name(contact)
    contact.additional_attributes&.dig('company_name').presence || contact.try(:company)&.name
  end

  def extract_shared_contact_id
    return @params[:shared_contact_id] unless @params.instance_of?(ActionController::Parameters)

    @params.permit(:shared_contact_id)[:shared_contact_id]
  end

  def split_contact_name(name)
    parts = name.to_s.strip.split(/\s+/, 2)
    [parts[0], parts[1]]
  end

  def normalized_share_phone(phone_number)
    parsed = TelephoneNumber.parse(phone_number)
    raise StandardError, 'Invalid phone number' unless parsed.valid?

    parsed.e164_number
  end
end
