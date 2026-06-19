module Custom::MessageSearch::MatchingIds
  MAX_RESULTS = Custom::ConversationMessageSearchFinder::MAX_RESULTS

  module_function

  def relation(scope:, query:, from:, gin_enabled:, unaccent_enabled:)
    filtered_scope = Custom::MessageSearch::FromFilter.apply(scope, from)

    if gin_enabled && !unaccent_enabled
      gin_relation(filtered_scope, query, unaccent_enabled: unaccent_enabled)
    else
      ilike_relation(filtered_scope, query, unaccent_enabled)
    end
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("GIN tsquery failed for in-conversation search, falling back to ILIKE: #{e.message}")
    ilike_relation(filtered_scope, query, unaccent_enabled)
  end

  def ilike_relation(scope, query, unaccent_enabled)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
    audio_type = Attachment.file_types[:audio]

    scope.left_joins(:attachments)
         .where(
           Custom::MessageSearch::ContentPredicate.sql(unaccent: unaccent_enabled),
           pattern: pattern,
           audio_type: audio_type
         )
         .select('messages.id')
         .distinct
         .reorder('messages.created_at DESC')
         .limit(MAX_RESULTS)
  end

  def gin_relation(filtered_scope, query, unaccent_enabled: false)
    tsquery = Custom::MessageSearch::Tsquery.build_phrase_query(query)
    return ilike_relation(filtered_scope, query, unaccent_enabled) if tsquery.blank?

    content_ids = filtered_scope.where('messages.content @@ to_tsquery(?)', tsquery).select('messages.id')
    transcription_ids = transcription_match_ids(filtered_scope, query)

    filtered_scope.where(id: content_ids)
                  .or(filtered_scope.where(id: transcription_ids))
                  .select('messages.id')
                  .distinct
                  .reorder('messages.created_at DESC')
                  .limit(MAX_RESULTS)
  end

  def transcription_match_ids(filtered_scope, query)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
    audio_type = Attachment.file_types[:audio]

    filtered_scope.left_joins(:attachments)
                  .where(
                    <<~SQL.squish,
                      attachments.file_type = :audio_type
                      AND (
                        attachments.meta->>'transcribed_text' ILIKE :pattern
                        OR attachments.meta->'transcription'->>'text' ILIKE :pattern
                      )
                    SQL
                    audio_type: audio_type,
                    pattern: pattern
                  )
                  .select('messages.id')
  end
end
