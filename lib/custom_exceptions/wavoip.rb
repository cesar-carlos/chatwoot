# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren -- Zeitwerk expects CustomExceptions::Wavoip module
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
# rubocop:enable Style/ClassAndModuleChildren
