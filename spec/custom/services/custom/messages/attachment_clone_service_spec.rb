# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Messages::AttachmentCloneService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:source_message) { create(:message, account: account, conversation: conversation) }
  let(:other_message) { create(:message, account: account, conversation: conversation) }

  def attach_image!(message)
    attachment = message.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(
      io: Rails.root.join('spec/assets/avatar.png').open,
      filename: 'avatar.png',
      content_type: 'image/png'
    )
    attachment.save!
    attachment
  end

  it 'clones attachments belonging to the source message when source_message_id is set' do
    source = attach_image!(source_message)
    other = attach_image!(other_message)

    blobs = described_class.new(
      account: account,
      attachment_ids: [source.id, other.id],
      source_message_id: source_message.id
    ).perform

    expect(blobs.size).to eq(1)
    expect(blobs.first).to be_a(ActiveStorage::Blob)
  end

  it 'clones any account attachment ids when source_message_id is blank' do
    source = attach_image!(source_message)
    other = attach_image!(other_message)

    blobs = described_class.new(
      account: account,
      attachment_ids: [source.id, other.id]
    ).perform

    expect(blobs.size).to eq(2)
  end
end
