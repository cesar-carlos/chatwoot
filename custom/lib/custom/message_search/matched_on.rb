module Custom::MessageSearch::MatchedOn
  module_function

  def compute(messages, query)
    by_id = {}
    cache = {}
    needle = Custom::MessageSearch::Unaccent.fold_text(query.to_s.strip, cache: cache)
    return by_id if needle.blank?

    messages.each do |message|
      by_id[message.id] = matched_on_for(message, needle, cache)
    end
    by_id
  end

  def matched_on_for(message, needle, cache)
    normalized = lambda do |text|
      Custom::MessageSearch::Unaccent.fold_text(text, cache: cache)
    end

    content_match = normalized.call(message.content.to_s).include?(needle)
    subject = message.content_attributes&.dig('email', 'subject').to_s
    subject_match = normalized.call(subject).include?(needle)
    transcription_match = message.attachments.any? do |attachment|
      next false unless attachment.file_type == 'audio'

      text = Custom::TranscriptionMetadata.read_text(attachment).to_s
      normalized.call(text).include?(needle)
    end

    return 'content' if content_match || subject_match
    return 'transcription' if transcription_match

    nil
  end
end
