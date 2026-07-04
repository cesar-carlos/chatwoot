# frozen_string_literal: true

class CustomExceptions::Wavoip::VoiceOnlyInbox < CustomExceptions::Base
  def message
    I18n.t('errors.wavoip.voice_only_inbox')
  end
end
