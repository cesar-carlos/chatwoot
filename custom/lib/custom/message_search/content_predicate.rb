module Custom::MessageSearch::ContentPredicate
  module_function

  def sql(alias_messages: 'messages', alias_attachments: 'attachments', unaccent: false)
    [
      ilike_expr("#{alias_messages}.content", unaccent: unaccent),
      ilike_expr("#{alias_messages}.content_attributes->'email'->>'subject'", unaccent: unaccent),
      audio_clause(alias_attachments, 'transcribed_text', unaccent: unaccent),
      audio_clause(alias_attachments, 'transcription', unaccent: unaccent)
    ].join(' OR ')
  end

  def audio_clause(alias_attachments, field, unaccent: false)
    column_sql = if field == 'transcribed_text'
                   "#{alias_attachments}.meta->>'transcribed_text'"
                 else
                   "#{alias_attachments}.meta->'transcription'->>'text'"
                 end

    "(#{alias_attachments}.file_type = :audio_type AND #{ilike_expr(column_sql, unaccent: unaccent)})"
  end

  def ilike_expr(column_sql, unaccent: false)
    if unaccent
      "unaccent_immutable(#{column_sql}) ILIKE unaccent_immutable(:pattern)"
    else
      "#{column_sql} ILIKE :pattern"
    end
  end
end
