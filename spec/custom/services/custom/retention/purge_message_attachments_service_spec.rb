require 'rails_helper'

RSpec.describe Custom::Retention::PurgeMessageAttachmentsService do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:message) do
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing)
    end
    let(:run_id) { 'test-run-id' }

    before do
      allow_any_instance_of(Inbox).to receive(:create_default_working_hours) # rubocop:disable RSpec/AnyInstance
    end

    def create_file_attachment(created_at:, parent_message: message)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('retention-test'),
        filename: 'test.txt',
        content_type: 'text/plain'
      )
      attachment = parent_message.attachments.create!(account: account, file_type: :file)
      attachment.file.attach(blob)
      attachment.update_column(:created_at, created_at) # rubocop:disable Rails/SkipsModelValidations
      attachment
    end

    def create_external_url_attachment(created_at:, parent_message: message)
      attachment = parent_message.attachments.create!(
        account: account,
        file_type: :image,
        external_url: 'https://example.com/photo.jpg'
      )
      attachment.update_column(:created_at, created_at) # rubocop:disable Rails/SkipsModelValidations
      attachment
    end

    it 'does not purge when retention is disabled' do
      attachment = create_file_attachment(created_at: 100.days.ago)

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'false',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result).to include(deleted_count: 0, has_more: false, failed_count: 0, bytes_freed: 0)
        expect(Attachment.exists?(attachment.id)).to be(true)
        expect(AttachmentRetentionEvent.count).to eq(0)
      end
    end

    it 'purges expired attachments and keeps the message' do
      attachment = create_file_attachment(created_at: 100.days.ago)

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                        MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'false' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result[:deleted_count]).to eq(1)
        expect(result[:has_more]).to be(false)
        expect(result[:failed_count]).to eq(0)
        expect(result[:bytes_freed]).to be_positive
        expect(Attachment.exists?(attachment.id)).to be(false)
        expect(Message.exists?(message.id)).to be(true)

        event = AttachmentRetentionEvent.find_by(attachment_id: attachment.id)
        expect(event).to have_attributes(status: 'purged', run_id: run_id, account_id: account.id)
      end
    end

    it 'does not destroy attachments in dry-run mode but records audit events' do
      attachment = create_file_attachment(created_at: 100.days.ago)

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                        MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'true' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result[:deleted_count]).to eq(1)
        expect(result[:has_more]).to be(false)
        expect(Attachment.exists?(attachment.id)).to be(true)

        event = AttachmentRetentionEvent.find_by(attachment_id: attachment.id)
        expect(event).to have_attributes(status: 'dry_run', run_id: run_id)
      end
    end

    it 'reports has_more when the per-run cap is exceeded' do
      message_two = create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing
      )
      create_file_attachment(created_at: 100.days.ago)
      create_file_attachment(created_at: 101.days.ago, parent_message: message_two)

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                        MESSAGE_ATTACHMENT_RETENTION_MAX_PURGE_PER_RUN: '1',
                        MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'false' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result[:deleted_count]).to eq(1)
        expect(result[:has_more]).to be(true)
        expect(Attachment.where(account_id: account.id).joins(:file_attachment).count).to eq(1)
      end
    end

    it 'purges expired attachments with only external_url' do
      attachment = create_external_url_attachment(created_at: 100.days.ago)

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                        MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'false' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result[:deleted_count]).to eq(1)
        expect(Attachment.exists?(attachment.id)).to be(false)
      end
    end

    it 'skips quarantined attachments after repeated failures' do
      attachment = create_file_attachment(created_at: 100.days.ago)
      create(
        :attachment_retention_failure,
        account: account,
        attachment_id: attachment.id,
        failure_count: Custom::Retention::Policy::DEFAULT_MAX_FAILURE_ATTEMPTS
      )

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                        MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'false' do
        GlobalConfig.clear_cache

        result = described_class.new(account: account, run_id: run_id).perform

        expect(result[:deleted_count]).to eq(0)
        expect(Attachment.exists?(attachment.id)).to be(true)
      end
    end

    it 'records only skipped_quarantine when failure threshold is reached' do
      attachment = create_file_attachment(created_at: 100.days.ago)
      create(
        :attachment_retention_failure,
        account: account,
        attachment_id: attachment.id,
        failure_count: Custom::Retention::Policy::DEFAULT_MAX_FAILURE_ATTEMPTS - 1
      )

      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90' do
        GlobalConfig.clear_cache

        service = described_class.new(account: account, run_id: run_id)
        quarantined = service.send(:failure_tracker).record_failure(attachment, 'storage unavailable')

        expect(quarantined).to be(true)
        events = AttachmentRetentionEvent.where(attachment_id: attachment.id)
        expect(events.pluck(:status)).to eq(['skipped_quarantine'])
      end
    end

    it 'reindexes the message when search indexing is enabled' do
      reindex_modes = []
      purged_message = message
      purged_message.define_singleton_method(:reindex) { |mode:| reindex_modes << mode }
      allow(purged_message).to receive(:should_index?).and_return(true)

      service = described_class.new(account: account, run_id: run_id)
      service.send(:reindex_message_for_search, purged_message)

      expect(reindex_modes).to eq([:async])
    end
  end
end
