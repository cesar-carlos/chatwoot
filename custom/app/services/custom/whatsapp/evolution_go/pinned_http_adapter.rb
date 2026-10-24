# frozen_string_literal: true

# Dials the IP UrlSafetyGuard already accepted and keeps the hostname for Host / TLS.
class Custom::Whatsapp::EvolutionGo::PinnedHttpAdapter < HTTParty::ConnectionAdapter
  def connection
    http = super
    http.ipaddr = options[:pinned_ip] if options[:pinned_ip].present?
    http
  end
end
