require 'rails_helper'

RSpec.describe Custom::Retention::Policy do
  describe '.enabled?' do
    it 'is disabled when no ENV or installation config is set' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: nil,
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: nil do
        InstallationConfig.where(name: described_class::ENABLED_KEY).delete_all
        GlobalConfig.clear_cache

        expect(described_class.enabled?).to be(false)
      end
    end

    it 'is enabled when ENV flag is true and days are positive' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '90' do
        GlobalConfig.clear_cache

        expect(described_class.enabled?).to be(true)
        expect(described_class.attachment_ttl).to eq(90.days)
      end
    end

    it 'is disabled when days are zero' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: '0' do
        GlobalConfig.clear_cache

        expect(described_class.enabled?).to be(false)
      end
    end
  end

  describe '.retention_days' do
    it 'defaults to 90 when enabled without explicit days' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                        MESSAGE_ATTACHMENT_RETENTION_DAYS: nil do
        InstallationConfig.where(name: described_class::DAYS_KEY).delete_all
        GlobalConfig.clear_cache

        expect(described_class.retention_days).to eq(90)
      end
    end
  end

  describe '.distribution_groups' do
    it 'defaults to 1 for daily processing of all accounts' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS: nil do
        expect(described_class.distribution_groups).to eq(1)
      end
    end

    it 'reads override from ENV' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS: '7' do
        expect(described_class.distribution_groups).to eq(7)
      end
    end
  end

  describe '.max_reenqueue_attempts' do
    it 'defaults to 100' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS: nil do
        expect(described_class.max_reenqueue_attempts).to eq(100)
      end
    end
  end

  describe '.dry_run?' do
    it 'defaults to false' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: nil do
        InstallationConfig.where(name: described_class::DRY_RUN_KEY).delete_all
        GlobalConfig.clear_cache

        expect(described_class.dry_run?).to be(false)
      end
    end

    it 'reads override from ENV' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: 'true' do
        expect(described_class.dry_run?).to be(true)
      end
    end

    it 'reads override from InstallationConfig when ENV is absent' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_DRY_RUN: nil do
        InstallationConfig.find_or_create_by!(name: described_class::DRY_RUN_KEY) do |config|
          config.value = 'true'
          config.locked = false
        end
        GlobalConfig.clear_cache

        expect(described_class.dry_run?).to be(true)
      end
    end
  end

  describe '.max_failure_attempts' do
    it 'defaults to 3' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_MAX_FAILURE_ATTEMPTS: nil do
        expect(described_class.max_failure_attempts).to eq(3)
      end
    end
  end

  describe '.audit_retention_days' do
    it 'defaults to 365' do
      with_modified_env MESSAGE_ATTACHMENT_RETENTION_AUDIT_RETENTION_DAYS: nil do
        expect(described_class.audit_retention_days).to eq(365)
      end
    end
  end
end
