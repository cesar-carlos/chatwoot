# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Llm::AccountCredential do
  let(:account) { create(:account) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  describe '.resolve' do
    it 'prefers the account OpenAI hook key' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

      expect(described_class.resolve(account)).to eq(api_key: 'hook-key', source: :hook)
    end

    it 'falls back to the system key when the hook is missing' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')

      expect(described_class.resolve(account)).to eq(api_key: 'system-key', source: :system)
    end

    it 'returns nil when neither hook nor system key is present' do
      expect(described_class.resolve(account)).to be_nil
    end

    it 'ignores disabled openai hooks' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')
      hook = create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
      hook.update_column(:status, Integrations::Hook.statuses['disabled']) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.resolve(account)).to eq(api_key: 'system-key', source: :system)
    end
  end

  describe '.using_account_hook?' do
    it 'is true when the resolved source is the account hook' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

      expect(described_class.using_account_hook?(account)).to be(true)
    end

    it 'is false when using the system key' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')

      expect(described_class.using_account_hook?(account)).to be(false)
    end
  end

  describe '.api_base' do
    it 'defaults to the OpenAI v1 endpoint' do
      expect(described_class.api_base).to eq('https://api.openai.com/v1')
    end

    it 'uses CAPTAIN_OPEN_AI_ENDPOINT when configured' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://example.com/')

      expect(described_class.api_base).to eq('https://example.com/v1')
    end
  end

  describe '.build_context' do
    let(:mock_context) { instance_double(RubyLLM::Context) }

    before do
      allow(RubyLLM).to receive(:context) do |&block|
        config = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
        block&.call(config)
        mock_context
      end
    end

    it 'returns the hook credential and a RubyLLM context' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

      credential, context = described_class.build_context(account)

      expect(credential).to eq(api_key: 'hook-key', source: :hook)
      expect(context).to eq(mock_context)
    end

    it 'raises when no credential is available' do
      expect do
        described_class.build_context(account)
      end.to raise_error(StandardError, I18n.t('captain.api_key_missing'))
    end
  end

  describe '.with_account_context' do
    let(:mock_context) { instance_double(RubyLLM::Context) }

    before do
      allow(RubyLLM).to receive(:context) do |&block|
        config = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
        block&.call(config)
        mock_context
      end
    end

    after do
      Thread.current[described_class::THREAD_CONTEXT_KEY] = nil
    end

    it 'yields credential/context and clears the thread slot afterward' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

      described_class.with_account_context(account) do |credential, context|
        expect(credential).to eq(api_key: 'hook-key', source: :hook)
        expect(context).to eq(mock_context)
        expect(described_class.thread_context).to eq(mock_context)
      end

      expect(described_class.thread_context).to be_nil
    end
  end

  describe '.openai_client_for' do
    it 'builds a client with the account hook key' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

      expect(OpenAI::Client).to receive(:new).with(
        hash_including(access_token: 'hook-key')
      ).and_return(instance_double(OpenAI::Client))

      described_class.openai_client_for(account)
    end
  end
end
