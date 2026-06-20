module Custom::MessageSearch::MatchedOn
  module_function

  def compute(messages, query)
    by_id = {}
    cache = {}
    needle = Custom::MessageSearch::Unaccent.normalize_text(query.to_s.strip, cache: cache)
    return by_id if needle.blank?

    messages.each do |message|
      by_id[message.id] = matched_on_for(message, needle, cache)
    end
    by_id
  end

  def matched_on_for(message, needle, cache)
    content_match = Custom::MessageSearch::Unaccent.normalize_text(message.content.to_s, cache: cache).include?(needle)
    subject = message.content_attributes&.dig('email', 'subject').to_s
    subject_match = Custom::MessageSearch::Unaccent.normalize_text(subject, cache: cache).include?(needle)
    transcription_match = message.attachments.any? do |attachment|
      next false unless attachment.file_type == 'audio'

      text = Custom::TranscriptionMetadata.read_text(attachment).to_s
      Custom::MessageSearch::Unaccent.normalize_text(text, cache: cache).include?(needle)
    end

    return 'content' if content_match || subject_match
    return 'transcription' if transcription_match

    nil
  end
end
