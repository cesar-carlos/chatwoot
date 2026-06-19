module Custom::MessageSearch::Unaccent
  module_function

  def extension_enabled?
    connection = ActiveRecord::Base.connection
    if connection.respond_to?(:extension_enabled?)
      connection.extension_enabled?('unaccent')
    else
      connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(
          ['SELECT true FROM pg_extension WHERE extname = ? LIMIT 1', 'unaccent']
        )
      ).present?
    end
  rescue StandardError
    false
  end

  def normalize_text(text, cache: nil)
    lowered = text.to_s.downcase
    return lowered unless extension_enabled?

    if cache
      return cache[lowered] if cache.key?(lowered)

      cache[lowered] = normalize_text_via_db(lowered)
      return cache[lowered]
    end

    normalize_text_via_db(lowered)
  end

  def normalize_text_via_db(lowered)
    quoted = ActiveRecord::Base.connection.quote(lowered)
    ActiveRecord::Base.connection.select_value("SELECT unaccent_immutable(#{quoted})") || lowered
  end
end
