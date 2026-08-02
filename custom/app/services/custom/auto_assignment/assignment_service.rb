# frozen_string_literal: true

# FORK: skip WhatsApp group conversations (@g.us) in Assignment V2 bulk runs.
module Custom::AutoAssignment::AssignmentService
  private

  def assignable?(conversation)
    return false if conversation.contact_inbox&.source_id.to_s.end_with?('@g.us')

    super
  end
end
