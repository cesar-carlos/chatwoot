# frozen_string_literal: true

# Blocks obviously malicious SSRF targets (cloud metadata / link-local addresses)
# for `evolution_go_server_check`, the only endpoint that issues an HTTP request
# to a user-supplied `base_url` before any inbox/channel exists.
#
# Private (RFC1918) and loopback ranges are intentionally NOT blocked: self-hosted
# Evolution Go instances commonly run on the same host, in the same Docker network,
# or on the same LAN as Chatwoot, and rejecting those would break legitimate setups.
#
# Unresolved hosts fail closed. `server_ok` connects to the IP this guard just
# accepted so a DNS change between the check and the socket cannot retarget the
# request at a link-local address.
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

  def self.destination_ips(url)
    new(url).destination_ips
  end

  def self.blocked_ip?(ip)
    addr = IPAddr.new(ip)
    BLOCKED_RANGES.any? { |range| range.include?(addr) }
  rescue IPAddr::Error
    true
  end

  def self.resolve_ips(host)
    literal = ip_literal(host)
    return [literal] if literal.present?

    Resolv.getaddresses(host).compact_blank
  rescue StandardError
    []
  end

  def self.ip_literal(host)
    token = host.to_s.delete_prefix('[').delete_suffix(']')
    return if token.blank?

    IPAddr.new(token).to_s
  rescue IPAddr::Error
    nil
  end

  def initialize(url)
    @url = url.to_s
  end

  def safe?
    ips = destination_ips
    ips.present? && ips.none? { |ip| self.class.blocked_ip?(ip) }
  rescue URI::InvalidURIError
    false
  end

  def destination_ips
    uri = URI.parse(@url)
    return [] if uri.host.blank? || ALLOWED_SCHEMES.exclude?(uri.scheme)

    self.class.resolve_ips(uri.host)
  end
end
