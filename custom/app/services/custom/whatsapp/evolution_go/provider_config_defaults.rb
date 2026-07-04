# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults
  DEFAULTS = {
    'ignore_groups' => true,
    'reject_call' => false,
    'msg_call' => '',
    'always_online' => false,
    'read_messages' => false,
    'ignore_status' => true,
    'proxy_enabled' => false,
    'proxy_host' => '',
    'proxy_port' => '',
    'proxy_username' => '',
    'proxy_password' => '',
    'sign_msg' => false,
    'sign_delimiter' => "\n",
    'mark_read_on_reply' => false,
    'mark_read_on_open' => true,
    'send_random_delay' => false,
    'notify_send_errors_private' => true,
    'convert_markdown_outbound' => true,
    'merge_brazil_contacts' => true,
    'send_templates_as_text' => true,
    'ignore_from_me_echo' => true,
    'connection_status' => 'close',
    'webhook_token' => nil,
    'webhook_subscribe' => %w[MESSAGE CONNECTION QRCODE READ_RECEIPT]
  }.freeze
end
