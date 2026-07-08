# frozen_string_literal: true

# Blocks obviously malicious SSRF targets (cloud metadata / link-local addresses)
# for `evolution_go_server_check`, the only endpoint that issues an HTTP request
# to a user-supplied `base_url` before any inbox/channel exists.
#
# Private (RFC1918) and loopback ranges are intentionally NOT blocked: self-hosted
# Evolution Go instances commonly run on the same host, in the same Docker network,
# or on the same LAN as Chatwoot, and rejecting those would break legitimate setups.
class Custom::Whatsapp::EvolutionGo::UrlSafetyGuard
  ALLOWED_SCHEMES = %w[http https].freeze
  BLOCKED_RANGES = [
    IPAddr.new('169.254.0.0/16'), # link-local, incl. AWS/GCP/Azure/DO metadata (169.254.169.254)
    IPAddr.new('fe80::/10'),      # IPv6 link-local
    IPAddr.new('fd00:ec2::254/128') # AWS IMDSv2 IPv6 metadata
  ].freeze

  def self.safe?(url)
    new(url).safe?
  end

  def initialize(url)
    @url = url.to_s
  end

  def safe?
    uri = URI.parse(@url)
    return false if uri.host.blank? || ALLOWED_SCHEMES.exclude?(uri.scheme)

    resolved_ips(uri.host).none? { |ip| blocked_ip?(ip) }
  rescue URI::InvalidURIError
    false
  end

  private

  # Fails open on resolution errors: the actual API call will simply fail to
  # connect, we only need to actively block known-bad literal targets here.
  def resolved_ips(host)
    Resolv.getaddresses(host)
  rescue StandardError
    []
  end

  def blocked_ip?(ip)
    addr = IPAddr.new(ip)
    BLOCKED_RANGES.any? { |range| range.include?(addr) }
  rescue IPAddr::Error
    false
  end
end
