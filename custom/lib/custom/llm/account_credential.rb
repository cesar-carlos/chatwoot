# frozen_string_literal: true

# Resolves OpenAI credentials for Captain (Copilot, Assistant V1/V2, FAQ/docs).
# Prefer the account OpenAI integration hook (BYOK), then fall back to the
# installation-wide CAPTAIN_OPEN_AI_API_KEY.
module Custom::Llm::AccountCredential
  THREAD_CONTEXT_KEY = :captain_byok_ruby_llm_context

  class << self
    def resolve(account)
      hook_credential(account) || system_credential
    end

    def using_account_hook?(account)
      resolve(account)&.dig(:source) == :hook
    end

    def api_base
      endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
      "#{endpoint.chomp('/')}/v1"
    end

    # Builds a RubyLLM::Context bound to the resolved account/system credential.
    # Raises when no key is available for the given account.
    def build_context(account)
      credential = require_credential!(account)
      Llm::Config.initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = credential[:api_key]
        config.openai_api_base = api_base
      end
      [credential, context]
    end

    # Agents::Runner creates Chat without context; stash BYOK context on the thread
    # so Custom::Llm::ChatByok can inject it into Chat.new (thread-safe per request).
    def with_account_context(account)
      credential, context = build_context(account)
      previous = Thread.current[THREAD_CONTEXT_KEY]
      Thread.current[THREAD_CONTEXT_KEY] = context
      yield(credential, context)
    ensure
      Thread.current[THREAD_CONTEXT_KEY] = previous
    end

    def thread_context
      Thread.current[THREAD_CONTEXT_KEY]
    end

    def require_credential!(account)
      credential = resolve(account)
      return credential if credential.present?

      Rails.logger.error("[Captain BYOK] API key missing for account=#{account&.id}")
      raise StandardError, I18n.t('captain.api_key_missing')
    end

    def openai_client_for(account)
      credential = require_credential!(account)
      endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
      OpenAI::Client.new(
        access_token: credential[:api_key],
        uri_base: endpoint.presence || 'https://api.openai.com/',
        log_errors: Rails.env.development?
      )
    end

    private

    def hook_credential(account)
      return if account.blank?

      key = account.hooks.find_by(app_id: 'openai', status: 'enabled')&.settings&.dig('api_key').presence
      { api_key: key, source: :hook } if key
    end

    def system_credential
      key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
      { api_key: key, source: :system } if key
    end
  end
end
