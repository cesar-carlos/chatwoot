# rubocop:disable Metrics/BlockLength
namespace :conversation_message_search do
  desc 'Smoke test in-conversation message search. Usage: rake conversation_message_search:smoke[account_id,conversation_id,query]'
  task :smoke, %i[account_id conversation_id query] => :environment do |_task, args|
    account = Account.find(args[:account_id])
    conversation = account.conversations.find_by!(display_id: args[:conversation_id])
    query = args[:query].presence || 'test'

    finder = Custom::ConversationMessageSearchFinder.new(
      conversation: conversation,
      query: query,
      page: 1
    )
    results = finder.perform

    puts "Search engine: #{finder.search_engine}"
    puts "Results: #{results.size} (has_more: #{finder.has_more?})"
    results.each do |message|
      matched_on = finder.matched_on_by_id[message.id]
      puts "- ##{message.id} [#{matched_on}] #{message.content.to_s.truncate(80)}"
    end
  end

  desc 'EXPLAIN ANALYZE for in-conversation search subquery. Usage: rake conversation_message_search:explain[conversation_id,query]'
  task :explain, %i[conversation_id query] => :environment do |_task, args|
    conversation = Conversation.find_by!(display_id: args[:conversation_id])
    query = args[:query].presence || 'test'
    finder = Custom::ConversationMessageSearchFinder.new(
      conversation: conversation,
      query: query,
      page: 1
    )

    unaccent = Custom::MessageSearch::Unaccent.extension_enabled?
    gin_enabled = conversation.account.feature_enabled?('search_with_gin')

    base_scope = conversation.messages
                             .where(message_type: %i[incoming outgoing template])
                             .where(Custom::MessageSearch::ContentAttributes.deleted_predicate)

    matching_ids = Custom::MessageSearch::MatchingIds.relation(
      scope: base_scope,
      query: query,
      from: nil,
      gin_enabled: gin_enabled,
      unaccent_enabled: unaccent
    )

    sql = base_scope.where(id: matching_ids)
                    .reorder(created_at: :desc)
                    .limit(Custom::ConversationMessageSearchFinder::PER_PAGE + 1)
                    .to_sql

    puts "Search engine (finder): #{finder.search_engine}"
    puts "EXPLAIN (ANALYZE, BUFFERS) for conversation ##{conversation.display_id}:"
    ActiveRecord::Base.connection.execute("EXPLAIN (ANALYZE, BUFFERS) #{sql}").values.flatten.each do |line|
      puts line
    end
  end

  desc 'OpenSearch reindex hints after search index field changes'
  task reindex_hints: :environment do
    puts <<~HINTS
      Conversation message search — OpenSearch reindex hints

      New indexed fields (require reindex for existing documents):
        - message_attributes.deleted (exclude deleted messages in queries)
        - attachments.transcribed_text (unified via Custom::TranscriptionMetadata.read_text)

      Prerequisites:
        - ChatwootApp.advanced_search_allowed? => #{ChatwootApp.advanced_search_allowed?}
        - Searchkick defined => #{defined?(Searchkick).present?}

      Per account (enable advanced_search / advanced_search_indexing as needed):
        bundle exec rails runner "Messages::ReindexService.new(account: Account.find(ACCOUNT_ID)).perform"

      Or bulk (see enterprise/lib/tasks/search.rake and script/reindex_single_account.rb).

      After reindex, verify deleted messages are excluded:
        rake conversation_message_search:smoke[ACCOUNT_ID,CONV_DISPLAY_ID,query]
    HINTS

    unless ChatwootApp.advanced_search_allowed? && defined?(Searchkick)
      puts 'OpenSearch is not available in this installation — SQL/ILIKE search is unaffected.'
    end
  end

  desc 'Print manual acceptance checklist (implementation-plan §11)'
  task acceptance: :environment do
    puts <<~CHECKLIST
      Conversation message search — acceptance matrix (§11)
      Mark each scenario after manual verification in staging/production.

      [ ] Query 0-1 chars — no request, hint visible
      [ ] Recent message — result, scroll, highlight
      [ ] Old message — merge, scroll, highlight
      [ ] Transcription-only match — mic badge + snippet
      [ ] Legacy transcribed_text key — result
      [ ] Audio without transcription — not in results
      [ ] Private note — badge visible
      [ ] Activity message — excluded
      [ ] Deleted message — excluded
      [ ] Email subject match
      [ ] Accent-insensitive (contrato/contráto)
      [ ] 16+ matches — 15 results, has_more true
      [ ] Page 2 — append without duplicates
      [ ] Rate limit — 429 + UI message
      [ ] Narrow viewport — panel without horizontal overflow

      Automated: rake conversation_message_search:smoke[ID,CONV_ID,query]
      Performance: rake conversation_message_search:explain[CONV_ID,query]
      OpenSearch reindex: rake conversation_message_search:reindex_hints
    CHECKLIST
  end
end
# rubocop:enable Metrics/BlockLength
