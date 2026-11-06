# frozen_string_literal: true

module Custom::Whatsapp::Import::ContactLookup
  private

  def locate_import_contact(phone)
    Custom::Whatsapp::Import::ContactLocator.new(
      account: runtime.account,
      inbox: runtime.inbox,
      merge_brazil: jid_resolver.merge_brazil_contacts?
    ).find(phone)
  end
end
