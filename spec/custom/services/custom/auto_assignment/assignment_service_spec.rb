# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::AutoAssignment::AssignmentService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:service) { AutoAssignment::AssignmentService.new(inbox: inbox) }

  describe '#assignable?' do
    it 'skips WhatsApp group conversations' do
      group_jid = '120363012345678901@g.us'
      contact = create(:contact, account: account, phone_number: nil, identifier: group_jid)
      contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: group_jid)
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        assignee: nil,
        status: :open
      )

      expect(service.send(:assignable?, conversation)).to be(false)
    end

    it 'still allows 1:1 conversations' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        assignee: nil,
        status: :open
      )

      expect(service.send(:assignable?, conversation)).to be(true)
    end
  end
end
