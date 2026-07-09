class Custom::ConversationMessageSearchFinder
  PER_PAGE = 15
  MAX_RESULTS = 100
  # Extra hits per OpenSearch round-trip to absorb stale deleted/activity docs after filter.
  OPENSEARCH_FETCH_PAD = 5
  OPENSEARCH_MAX_ROUNDS = 5

  attr_reader :matched_on_by_id

  def initialize(conversation:, query:, page: 1, from: nil)
    @conversation = conversation
    @account = conversation.account
    @query = query
    @page = page
    @from = from.to_s.strip.presence
    @has_more = false
    @matched_on_by_id = {}
  end

  def perform
    results = if opensearch_enabled?
                perform_opensearch
              else
                perform_sql
              end

    @matched_on_by_id = Custom::MessageSearch::MatchedOn.compute(results, @query)
    offset = (@page - 1) * PER_PAGE
    @has_more = results.size > PER_PAGE && (offset + PER_PAGE) < MAX_RESULTS
    results.first(PER_PAGE)
  end

  # rubocop:disable Naming/PredicateName -- API meta field is has_more
  def has_more?
    @has_more
  end
  # rubocop:enable Naming/PredicateName

  def search_engine
    return 'opensearch' if opensearch_enabled?
    return 'ilike_unaccent' if gin_enabled? && unaccent_enabled?
    return 'gin' if gin_enabled?

    unaccent_enabled? ? 'ilike_unaccent' : 'ilike'
  end

  private

  def perform_sql
    scoped_messages.to_a
  end

  def perform_opensearch
    page_offset = (@page - 1) * PER_PAGE
    return [] if page_offset >= MAX_RESULTS

    collect_opensearch_page(page_offset)
  rescue Faraday::ConnectionFailed, Searchkick::Error, Elasticsearch::Transport::Transport::Error => e
    Rails.logger.warn("OpenSearch unavailable for in-conversation search, falling back to SQL: #{e.message}")
    perform_sql
  end

  def collect_opensearch_page(page_offset)
    target = [PER_PAGE + 1, MAX_RESULTS - page_offset].min
    collected = []
    skipped = 0
    cursor = 0

    OPENSEARCH_MAX_ROUNDS.times do
      batch, batch_size = next_opensearch_batch(cursor, page_offset, skipped, target, collected.size)
      break if batch.blank?

      skipped, collected = absorb_opensearch_batch(batch, page_offset, skipped, collected, target)
      cursor += batch.size
      break if collected.size >= target || batch.size < batch_size
    end

    collected
  end

  def next_opensearch_batch(cursor, page_offset, skipped, target, collected_size)
    remaining_cap = MAX_RESULTS - cursor
    return [[], 0] if remaining_cap <= 0

    still_need = (page_offset - skipped) + (target - collected_size)
    return [[], 0] if still_need <= 0

    batch_size = [still_need + OPENSEARCH_FETCH_PAD, remaining_cap].min
    [fetch_opensearch_batch(cursor, batch_size), batch_size]
  end

  def absorb_opensearch_batch(batch, page_offset, skipped, collected, target)
    filter_searchable_messages(batch).each do |message|
      if skipped < page_offset
        skipped += 1
        next
      end

      collected << message
      break if collected.size >= target
    end

    [skipped, collected]
  end

  def fetch_opensearch_batch(offset, limit)
    Array(
      Message.search(
        @query.to_s.strip,
        fields: %w[content attachments.transcribed_text content_attributes.email.subject],
        where: Custom::MessageSearch::FromFilter.opensearch_conditions(@conversation, @from),
        order: { created_at: :desc },
        offset: offset,
        limit: limit,
        load: true,
        includes: [:attachments, :sender]
      )
    )
  end

  def scoped_messages
    offset = (@page - 1) * PER_PAGE
    return Message.none if offset >= MAX_RESULTS

    limit = [PER_PAGE + 1, MAX_RESULTS - offset].min

    @conversation.messages
                 .where(id: matching_message_ids)
                 .includes(:attachments, :sender)
                 .reorder(created_at: :desc)
                 .offset(offset)
                 .limit(limit)
  end

  def matching_message_ids
    Custom::MessageSearch::MatchingIds.relation(
      scope: base_search_scope,
      query: @query,
      from: @from,
      gin_enabled: gin_enabled?,
      unaccent_enabled: unaccent_enabled?
    )
  end

  def base_search_scope
    @conversation.messages
                 .where(message_type: %i[incoming outgoing template])
                 .where(Custom::MessageSearch::ContentAttributes.deleted_predicate)
  end

  def unaccent_enabled?
    @unaccent_enabled ||= Custom::MessageSearch::Unaccent.extension_enabled?
  end

  def gin_enabled?
    @account.feature_enabled?('search_with_gin')
  end

  def opensearch_enabled?
    return false unless defined?(Searchkick)
    return false unless ChatwootApp.advanced_search_allowed?
    return false unless @account.feature_enabled?('advanced_search')

    true
  end

  def filter_searchable_messages(messages)
    messages.select { |message| searchable_message?(message) }
  end

  def searchable_message?(message)
    message.message_type.in?(%w[incoming outgoing template]) && !message.deleted
  end
end
