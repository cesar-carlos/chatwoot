module Custom::SearchService
  private

  def filter_messages_with_like # rubocop:disable Metrics/AbcSize
    base_query = message_base_query
    base_query = apply_message_filters(base_query)
    return base_query.reorder('created_at DESC').page(params[:page]).per(15) if search_query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_query)}%"
    audio_type = Attachment.file_types[:audio]
    predicate = Custom::MessageSearch::ContentPredicate.sql(
      unaccent: Custom::MessageSearch::Unaccent.extension_enabled?
    )

    matching_ids = base_query.left_joins(:attachments)
                             .where(predicate, pattern: pattern, audio_type: audio_type)
                             .select('messages.id')
                             .distinct
                             .reorder(nil)

    base_query.where(id: matching_ids)
              .reorder('created_at DESC')
              .page(params[:page])
              .per(15)
  end

  def filter_messages_with_gin # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return filter_messages_with_like if Custom::MessageSearch::Unaccent.extension_enabled?

    base_query = message_base_query
    base_query = apply_message_filters(base_query)
    return base_query.reorder('created_at DESC').page(params[:page]).per(15) if search_query.blank?

    tsquery = Custom::MessageSearch::Tsquery.build_phrase_query(search_query)
    return filter_messages_with_like if tsquery.blank?

    content_ids = base_query.where('messages.content @@ to_tsquery(?)', tsquery)
                            .select('messages.id')

    transcription_ids = global_search_transcription_ids(base_query)
    subject_ids = Custom::MessageSearch::MatchingIds.email_subject_match_ids(
      base_query,
      search_query,
      unaccent_enabled: false
    )

    base_query.where(id: content_ids)
              .or(base_query.where(id: transcription_ids))
              .or(base_query.where(id: subject_ids))
              .reorder('created_at DESC')
              .page(params[:page])
              .per(15)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("GIN tsquery failed for global search, falling back to ILIKE: #{e.message}")
    filter_messages_with_like
  end

  def global_search_transcription_ids(base_query)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_query)}%"
    audio_type = Attachment.file_types[:audio]

    base_query.left_joins(:attachments)
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
