require 'rails_helper'

RSpec.describe Custom::ConversationMessageSearchFinder do
  subject(:finder) do
    described_class.new(
      conversation: conversation,
      query: query,
      page: page,
      from: from
    )
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:contact) { conversation.contact }
  let(:agent) { create(:user, account: account) }
  let(:query) { 'contract' }
  let(:page) { 1 }
  let(:from) { nil }

  describe '#perform' do
    before do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'Please review the contract terms',
        message_type: :incoming,
        sender: contact
      )
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'Unrelated hello message',
        message_type: :outgoing,
        sender: agent
      )
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'contract activity noise',
        message_type: :activity
      )
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'deleted contract copy',
        message_type: :incoming,
        sender: contact,
        content_attributes: { deleted: true }
      )
    end

    it 'returns ILIKE matches and excludes activity and deleted messages' do
      results = finder.perform
      matching_message = conversation.messages.find_by('content LIKE ?', '%contract terms%')

      expect(results.map(&:id)).to eq([matching_message.id])
      expect(finder.matched_on_by_id[matching_message.id]).to eq('content')
    end

    context 'when filtering by sender' do
      let(:from) { 'agent' }

      before do
        create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: 'agent contract update',
          message_type: :outgoing,
          sender: agent
        )
      end

      it 'returns only messages from agents' do
        results = finder.perform

        expect(results.map(&:sender_type).uniq).to eq(['User'])
        expect(results.all? { |message| message.content.include?('contract') }).to be(true)
      end
    end

    context 'when pagination exceeds one page' do
      before do
        16.times do |index|
          create(
            :message,
            conversation: conversation,
            account: account,
            inbox: inbox,
            content: "contract page #{index}",
            message_type: :incoming,
            sender: contact,
            created_at: (index + 1).minutes.ago
          )
        end
      end

      it 'returns PER_PAGE results and sets has_more' do
        results = finder.perform

        expect(results.length).to eq(described_class::PER_PAGE)
        expect(finder.has_more?).to be(true)
      end
    end

    context 'when query matches email subject' do
      let(:query) { 'invoice' }
      let!(:email_message) do
        create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: 'Please see attached',
          message_type: :incoming,
          sender: contact,
          content_attributes: { email: { subject: 'Invoice for March' } }
        )
      end

      it 'returns the message with matched_on content' do
        results = finder.perform

        expect(results.map(&:id)).to include(email_message.id)
        expect(finder.matched_on_by_id[email_message.id]).to eq('content')
      end
    end

    context 'when unaccent extension is enabled' do
      before do
        allow(Custom::MessageSearch::Unaccent).to receive(:extension_enabled?).and_return(true)
      end

      it 'reports ilike_unaccent search engine' do
        expect(finder.search_engine).to eq('ilike_unaccent')
      end

      it 'matches accent-insensitive content when unaccent SQL is available', if: Custom::MessageSearch::Unaccent.extension_enabled? do
        create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: 'Precisamos revisar o contráto',
          message_type: :incoming,
          sender: contact
        )

        accent_finder = described_class.new(conversation: conversation, query: 'contrato', page: 1)
        results = accent_finder.perform

        expect(results.length).to eq(1)
        expect(results.first.content).to include('contráto')
      end
    end

    context 'when search_with_gin is enabled' do
      before do
        allow(Custom::MessageSearch::Unaccent).to receive(:extension_enabled?).and_return(false)
        account.enable_features!('search_with_gin')
      end

      it 'reports gin search engine' do
        expect(finder.search_engine).to eq('gin')
      end

      it 'returns messages matching email subject' do
        email_message = create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: 'Please see attached',
          message_type: :incoming,
          sender: contact,
          content_attributes: { email: { subject: 'Invoice for March' } }
        )
        subject_finder = described_class.new(conversation: conversation, query: 'invoice', page: 1)

        results = subject_finder.perform

        expect(results.map(&:id)).to include(email_message.id)
      end
    end

    context 'when query matches transcription metadata' do
      let(:query) { 'voicemail' }
      let!(:audio_message) do
        create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: '',
          message_type: :incoming,
          sender: contact
        )
      end

      before do
        audio_message.attachments.create!(
          account: account,
          file_type: :audio,
          meta: {
            'transcription' => {
              'text' => 'Please check the voicemail transcript',
              'state' => 'success'
            }
          }
        )
      end

      it 'returns the audio message with matched_on transcription' do
        results = finder.perform

        expect(results.map(&:id)).to include(audio_message.id)
        expect(finder.matched_on_by_id[audio_message.id]).to eq('transcription')
      end
    end
  end

  describe '#search_engine' do
    it 'defaults to ilike or ilike_unaccent' do
      expect(finder.search_engine).to match(/\Ailike/)
    end
  end

  describe 'when opensearch is enabled' do
    subject(:opensearch_finder) do
      described_class.new(conversation: conversation, query: 'contract', page: 1)
    end

    let(:valid_message) do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'opensearch contract hit',
        message_type: :incoming,
        sender: contact
      )
    end
    let(:deleted_message) do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'deleted contract copy',
        message_type: :incoming,
        sender: contact,
        content_attributes: { deleted: true }
      )
    end
    let(:activity_message) do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        content: 'contract activity noise',
        message_type: :activity
      )
    end

    before do
      valid_message
      deleted_message
      activity_message
      allow(opensearch_finder).to receive(:opensearch_enabled?).and_return(true)
    end

    it 'reports opensearch search engine' do
      expect(opensearch_finder.search_engine).to eq('opensearch')
    end

    it 'filters deleted and activity messages from opensearch hits' do
      filtered = opensearch_finder.send(
        :filter_searchable_messages,
        [deleted_message, activity_message, valid_message]
      )

      expect(filtered.map(&:id)).to eq([valid_message.id])
    end

    it 'falls back to sql when opensearch is unavailable' do
      Message.define_singleton_method(:search) do |*_args, **_kwargs|
        raise Faraday::ConnectionFailed, 'cluster down'
      end

      results = opensearch_finder.send(:perform_opensearch)

      expect(results.map(&:id)).to include(valid_message.id)
    ensure
      Message.singleton_class.remove_method(:search)
    end
  end
end
