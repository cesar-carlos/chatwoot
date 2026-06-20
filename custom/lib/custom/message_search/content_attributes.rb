module Custom::MessageSearch::ContentAttributes
  module_function

  # Rails `store` serializes content_attributes as a JSON string value, not a JSON object.
  def jsonb_sql(column: 'messages.content_attributes')
    "(#{column} #>> '{}')::jsonb"
  end

  def deleted_predicate(column: 'messages.content_attributes')
    "COALESCE(#{jsonb_sql(column: column)}->>'deleted', 'false') != 'true'"
  end

  def email_subject_sql(column: 'messages.content_attributes')
    "#{jsonb_sql(column: column)}->'email'->>'subject'"
  end
end
