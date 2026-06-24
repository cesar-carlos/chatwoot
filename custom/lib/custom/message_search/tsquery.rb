module Custom::MessageSearch::Tsquery
  SPECIAL_CHARS = /[&|!():*'\\]/u

  module_function

  def build_phrase_query(text)
    text.to_s.strip.split(/\s+/).filter_map do |term|
      sanitized = sanitize_term(term)
      sanitized.presence
    end.join(' & ')
  end

  def sanitize_term(term)
    term.to_s.gsub(SPECIAL_CHARS, ' ').strip
  end
end
