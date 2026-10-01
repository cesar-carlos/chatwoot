class Custom::Notification::BrowserSubscriptionValidator
  def self.endpoint_valid?(value)
    return false unless value.is_a?(String)

    uri = URI.parse(value)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end

  def self.valid?(attributes)
    return false unless attributes.respond_to?(:[])
    return false unless endpoint_valid?(attributes[:endpoint])

    valid_public_key?(decode(attributes[:p256dh])) && decode(attributes[:auth])&.bytesize == 16
  end

  def self.decode(value)
    return unless value.is_a?(String) && value.match?(%r{\A[A-Za-z0-9+/_-]+={0,2}\z})

    Base64.strict_decode64(value.tr('-_', '+/').ljust((value.length + 3) / 4 * 4, '='))
  rescue ArgumentError
    nil
  end
  private_class_method :decode

  def self.valid_public_key?(key)
    return false unless key&.bytesize == 65 && key.getbyte(0) == 4

    OpenSSL::PKey::EC::Point.new(OpenSSL::PKey::EC::Group.new('prime256v1'), OpenSSL::BN.new(key, 2)).on_curve?
  rescue OpenSSL::OpenSSLError
    false
  end
  private_class_method :valid_public_key?
end
