# frozen_string_literal: true

module Custom::ContactPolicy
  # FORK: MoreActions → sync contact info/avatar via Evolution Go
  def evolution_go_sync?
    update?
  end
end
