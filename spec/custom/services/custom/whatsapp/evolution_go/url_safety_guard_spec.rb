# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::UrlSafetyGuard do
  describe '.safe?' do
    it 'rejects blank or invalid urls' do
      expect(described_class.safe?('')).to be false
      expect(described_class.safe?('not a url')).to be false
    end

    it 'rejects non-http(s) schemes' do
      expect(described_class.safe?('ftp://example.com')).to be false
      expect(described_class.safe?('file:///etc/passwd')).to be false
    end

    it 'blocks the cloud metadata IP literal' do
      expect(described_class.safe?('http://169.254.169.254/latest/meta-data')).to be false
    end

    it 'blocks link-local hosts that resolve to 169.254.0.0/16' do
      allow(Resolv).to receive(:getaddresses).with('metadata.internal').and_return(['169.254.169.254'])

      expect(described_class.safe?('http://metadata.internal')).to be false
    end

    it 'allows private/loopback urls used by self-hosted setups' do
      expect(described_class.safe?('http://localhost:8080')).to be true
      expect(described_class.safe?('http://127.0.0.1:8080')).to be true
      expect(described_class.safe?('http://192.168.1.50:8080')).to be true
      expect(described_class.safe?('http://10.0.0.5:8080')).to be true
    end

    it 'allows normal public urls' do
      expect(described_class.safe?('https://evogo.example.com')).to be true
    end

    it 'fails open when DNS resolution errors out' do
      allow(Resolv).to receive(:getaddresses).and_raise(SocketError, 'boom')

      expect(described_class.safe?('https://unresolvable.example.com')).to be true
    end
  end
end
