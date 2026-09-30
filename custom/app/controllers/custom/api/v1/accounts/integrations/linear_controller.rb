# frozen_string_literal: true

module Custom::Api::V1::Accounts::Integrations::LinearController
  private

  def fetch_conversation
    super
    authorize @conversation, :show?
  end
end
