module Custom::MessageSearch::Unaccent
  module_function

  def extension_enabled?
    return @extension_enabled if defined?(@extension_enabled)

    @extension_enabled = check_extension_enabled
  end

  def reset_extension_enabled_cache!
    remove_instance_variable(:@extension_enabled) if defined?(@extension_enabled)
  end

  def fold_text(text, cache: nil)
    lowered = text.to_s.downcase
    if cache
      return cache[lowered] if cache.key?(lowered)

      cache[lowered] = fold_text_value(lowered)
      return cache[lowered]
    end

    fold_text_value(lowered)
  end

  def normalize_text(text, cache: nil, unaccent: nil)
    lowered = text.to_s.downcase
    unaccent = extension_enabled? if unaccent.nil?
    return lowered unless unaccent

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

  def fold_text_value(lowered)
    lowered.unicode_normalize(:nfd).gsub(/\p{M}/, '')
  end
  private_class_method :fold_text_value

  def check_extension_enabled
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
  private_class_method :check_extension_enabled
end
