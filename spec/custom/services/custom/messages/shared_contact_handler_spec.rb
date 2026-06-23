require 'rails_helper'

RSpec.describe Custom::Messages::SharedContactHandler do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
  let(:contact) { create(:contact, account: account, name: 'Jane Doe', phone_number: '+918660944581') }
  let(:message) do
    conversation.messages.build(
      account_id: account.id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing
    )
  end
  let(:params) { { shared_contact_id: contact.id } }
  let(:attachments) { nil }

  def attach_shared_contact
    described_class.new(
      account: account,
      conversation: conversation,
      params: params,
      attachments: attachments
    ).attach_to(message)
  end

  describe '#attach_to' do
    it 'creates a contact attachment with E.164 phone and meta' do
      attach_shared_contact

      attachment = message.attachments.first
      expect(attachment.file_type).to eq('contact')
      expect(attachment.fallback_title).to eq('+918660944581')
      expect(attachment.meta).to include('firstName' => 'Jane', 'lastName' => 'Doe')
    end

    context 'when shared_contact_id is blank' do
      let(:params) { {} }

      it 'does not create an attachment' do
        attach_shared_contact
        expect(message.attachments).to be_empty
      end
    end

    context 'when contact has no phone number' do
      let(:contact) { create(:contact, account: account, name: 'Jane Doe', phone_number: nil) }

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Contact phone number required')
      end
    end

    context 'when channel does not support contact sharing' do
      let(:api_channel) { create(:channel_api, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: api_channel.inbox) }

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Channel does not support contact sharing')
      end
    end

    context 'when file attachments are also present' do
      let(:attachments) do
        [fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')]
      end

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Cannot mix shared contact with file attachments')
      end
    end

    context 'when private is true' do
      let(:params) { { shared_contact_id: contact.id, private: true } }

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Cannot send shared contact as private note')
      end
    end

    context 'when content is present' do
      let(:params) { { shared_contact_id: contact.id, content: 'hello' } }

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Cannot send shared contact with message content')
      end
    end

    context 'when phone number is invalid' do
      let(:contact) do
        create(:contact, account: account, name: 'Jane Doe', phone_number: '+918660944581').tap do |record|
          record.update_column(:phone_number, 'not-a-phone') # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Invalid phone number')
      end
    end

    context 'when user lacks share permission' do
      let(:user) { create(:user, account: account) }

      def attach_shared_contact
        described_class.new(
          account: account,
          conversation: conversation,
          params: params,
          attachments: attachments,
          user: user
        ).attach_to(message)
      end

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        allow(account_user).to receive(:permissions).and_return(['conversation_manage'])
      end

      it 'raises an error' do
        expect { attach_shared_contact }.to raise_error(StandardError, 'Not authorized to share this contact')
      end
    end
  end
end
