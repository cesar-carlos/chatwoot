# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren -- Zeitwerk expects CustomExceptions::Conversation module
module CustomExceptions::Conversation
  class OpenAssignedToOtherAgent < CustomExceptions::Base
    def message
      I18n.t('errors.conversations.open_assigned_to_other_agent')
    end

    def http_status
      422
    end
  end

  class OutsidePermissionScope < CustomExceptions::Base
    def message
      I18n.t('errors.conversations.outside_permission_scope')
    end

    def http_status
      422
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
