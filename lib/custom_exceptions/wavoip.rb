# frozen_string_literal: true

module CustomExceptions::Wavoip
  class VoiceOnlyInbox < CustomExceptions::Base
    def message
      I18n.t('errors.wavoip.voice_only_inbox')
    end

    def http_status
      422
    end
  end
end
