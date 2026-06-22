require 'rails_helper'

RSpec.describe Custom::Retention::OperationalAlert do
  describe '.reenqueue_limit_reached' do
    let(:purge_result) do
      { deleted_count: 10, has_more: true, failed_count: 1, bytes_freed: 1000 }
    end

    it 'logs a warning payload' do
      expect(Rails.logger).to receive(:warn).with(
        a_string_including('reenqueue_limit_reached', '"account_id":42')
      )

      described_class.reenqueue_limit_reached(account_id: 42, attempt: 100, purge_result: purge_result)
    end

    it 'reports to Sentry in production when DSN is configured' do
      sentry = Class.new do
        def self.capture_message(*) end

        def self.with_scope
          scope = Object.new
          def scope.set_tags(*) end
          def scope.set_context(*) end
          yield scope
        end
      end
      stub_const('Sentry', sentry)
      allow(Rails.env).to receive(:to_s).and_return('production')

      with_modified_env SENTRY_DSN: 'https://example@sentry.io/1' do
        expect(Sentry).to receive(:capture_message).with(
          'Message attachment retention reenqueue limit reached',
          level: :warning
        )

        described_class.reenqueue_limit_reached(account_id: 42, attempt: 100, purge_result: purge_result)
      end
    end

    it 'does not report to Sentry outside production or staging' do
      sentry = Class.new do
        def self.capture_message(*) end

        def self.with_scope
          yield Object.new
        end
      end
      stub_const('Sentry', sentry)
      allow(Rails.env).to receive(:to_s).and_return('development')

      with_modified_env SENTRY_DSN: 'https://example@sentry.io/1' do
        expect(Sentry).not_to receive(:capture_message)

        described_class.reenqueue_limit_reached(account_id: 42, attempt: 100, purge_result: purge_result)
      end
    end
  end
end
