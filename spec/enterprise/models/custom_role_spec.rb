require 'rails_helper'

RSpec.describe CustomRole, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:account_users).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'includes conversation_team_unassigned_manage in PERMISSIONS' do
      expect(described_class::PERMISSIONS).to include('conversation_team_unassigned_manage')
    end
  end
end
