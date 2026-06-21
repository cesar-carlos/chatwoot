# frozen_string_literal: true

class Custom::Whatsapp::Evolution::Import::RemoteJidsCollector
  include Custom::Whatsapp::Evolution::Import::JidHelpers

  BATCH_SIZE = Custom::Whatsapp::Evolution::ImportService::BATCH_SIZE
  RATE_LIMIT_SLEEP = Custom::Whatsapp::Evolution::ImportService::RATE_LIMIT_SLEEP

  def initialize(runtime:, api_client:)
    @runtime = runtime
    @api_client = api_client
  end

  def collect!
    jids = []
    page = 1

    loop do
      response = @api_client.find_contacts(page: page, offset: BATCH_SIZE)
      Custom::Whatsapp::Evolution::ApiClient.raise_unless_success!(
        response,
        'Failed to fetch Evolution contacts for import'
      )

      contacts = Array.wrap(response.parsed_response)
      break if contacts.blank?

      contacts.each do |record|
        jid = record['remoteJid'].to_s
        jids << jid if jid.present? && !skip_remote_jid?(jid)
      end

      break if contacts.size < BATCH_SIZE

      page += 1
      sleep(RATE_LIMIT_SLEEP)
    end

    jids.uniq
  end

  private

  attr_reader :runtime
end
