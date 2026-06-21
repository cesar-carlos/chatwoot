# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ProviderConfig do
  describe '.runtime_only?' do
    it 'returns true for runtime keys only' do
      expect(described_class.runtime_only?('connection_status' => 'open')).to be(true)
      expect(described_class.runtime_only?(
               'last_qr_base64' => 'abc',
               'connection_status' => 'connecting'
             )).to be(true)
    end

    it 'returns false when syncable or credential keys are included' do
      expect(described_class.runtime_only?('groups_ignore' => false)).to be(false)
      expect(described_class.runtime_only?('api_key' => 'new-key')).to be(false)
    end
  end

  describe '.syncable_change?' do
    let(:before_config) { described_class.build('groups_ignore' => true) }

    it 'detects syncable setting changes' do
      after_config = before_config.merge('groups_ignore' => false)
      expect(described_class.syncable_change?(before_config, after_config)).to be(true)
    end

    it 'ignores runtime-only changes' do
      after_config = before_config.merge('connection_status' => 'open')
      expect(described_class.syncable_change?(before_config, after_config)).to be(false)
    end
  end

  describe '.credential_change?' do
    let(:before_config) { described_class.build('api_key' => 'old-key') }

    it 'detects credential changes' do
      after_config = before_config.merge('api_key' => 'new-key')
      expect(described_class.credential_change?(before_config, after_config)).to be(true)
    end

    it 'ignores chatwoot-only settings' do
      after_config = before_config.merge('sign_msg' => true)
      expect(described_class.credential_change?(before_config, after_config)).to be(false)
    end
  end
end
