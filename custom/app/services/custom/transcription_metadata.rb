class Custom::TranscriptionMetadata
  STATES = %w[pending processing success error].freeze
  PROCESSING_STALE_TTL = Custom::Transcription::LockManager::LOCK_TTL

  class << self
    def read_text(attachment)
      return '' unless attachment&.meta.is_a?(Hash)

      meta = attachment.meta
      transcription = meta['transcription']
      return transcription['text'].to_s if transcription.is_a?(Hash) && transcription['text'].present?

      meta['transcribed_text'].to_s
    end

    def read_state(attachment)
      return nil unless attachment&.meta.is_a?(Hash)

      state = attachment.meta.dig('transcription', 'state')
      return state if state.present?

      read_text(attachment).present? ? 'success' : nil
    end

    def read_error(attachment)
      return nil unless attachment&.meta.is_a?(Hash)

      attachment.meta.dig('transcription', 'error')
    end

    def read_started_at(attachment)
      return nil unless attachment&.meta.is_a?(Hash)

      transcription = attachment.meta['transcription']
      return nil unless transcription.is_a?(Hash)

      transcription['started_at'] || transcription['transcribed_at']
    end

    def stale_processing?(attachment)
      return false unless read_state(attachment) == 'processing'

      started_at = read_started_at(attachment)
      return true if started_at.blank?

      Time.current.to_i - started_at.to_i > PROCESSING_STALE_TTL.to_i
    end

    def clear_processing_state!(attachment)
      current_meta = attachment.meta.to_h
      transcription = current_meta['transcription']
      return unless transcription.is_a?(Hash)
      return unless %w[processing error].include?(transcription['state'])

      current_meta.delete('transcription')
      attachment.update!(meta: current_meta)
    end

    def actively_processing?(attachment, lock_manager:, force_refresh: false)
      return false if force_refresh
      return false unless read_state(attachment) == 'processing'
      return false if stale_processing?(attachment)

      lock_manager.locked?
    end

    def success_cache?(attachment)
      read_state(attachment) == 'success' && read_text(attachment).present?
    end

    def write_transcription(attachment, data)
      current_meta = attachment.meta.to_h
      transcription_data = data.deep_stringify_keys

      current_meta['transcription'] = transcription_data
      current_meta['transcribed_text'] = transcription_data['text'] if transcription_data['text'].present?

      attachment.update!(meta: current_meta)
    end

    def format_cached_response(cached_data)
      data = cached_data.deep_stringify_keys
      {
        text: data['text'],
        state: data['state'],
        provider: data['provider'],
        model: data['model'],
        metadata: data['metadata'] || {},
        error: data['error'],
        cached: true
      }
    end
  end
end
