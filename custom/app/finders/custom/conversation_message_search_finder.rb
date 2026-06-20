class Custom::ConversationMessageSearchFinder
  PER_PAGE = 15
  MAX_RESULTS = 100

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
    offset = (@page - 1) * PER_PAGE
    return [] if offset >= MAX_RESULTS

    limit = [PER_PAGE + 1, MAX_RESULTS - offset].min

    results = Message.search(
      @query.to_s.strip,
      fields: %w[content attachments.transcribed_text content_attributes.email.subject],
      where: Custom::MessageSearch::FromFilter.opensearch_conditions(@conversation, @from),
      order: { created_at: :desc },
      offset: offset,
      limit: limit,
      load: true,
      includes: [:attachments, :sender]
    )

    Array(results)
  rescue Faraday::ConnectionFailed, Searchkick::Error, Elasticsearch::Transport::Transport::Error => e
    Rails.logger.warn("OpenSearch unavailable for in-conversation search, falling back to SQL: #{e.message}")
    perform_sql
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
end
