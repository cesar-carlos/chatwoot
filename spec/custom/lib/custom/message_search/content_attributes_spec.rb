# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::MessageSearch::ContentAttributes do
  describe '.deleted_predicate' do
    it 'excludes messages marked deleted in content_attributes store JSON' do
      account = create(:account)
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      contact = conversation.contact

      deleted_message = create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'deleted contract copy',
        message_type: :incoming,
        sender: contact,
        content_attributes: { deleted: true }
      )

      scope = conversation.messages.where(described_class.deleted_predicate)

      expect(scope).not_to exist(deleted_message.id)
    end
  end

  describe '.email_subject_sql' do
    it 'reads email subject from store-serialized JSON' do
      account = create(:account)
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      contact = conversation.contact

      message = create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'Please see attached',
        message_type: :incoming,
        sender: contact,
        content_attributes: { email: { subject: 'Invoice for March' } }
      )

      sql = described_class.email_subject_sql
      result = conversation.messages.where("#{sql} ILIKE ?", '%invoice%')

      expect(result).to exist(message.id)
    end
  end
end
