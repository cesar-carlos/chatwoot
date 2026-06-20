# frozen_string_literal: true

FactoryBot.define do
  factory :channel_wavoip, class: 'Channel::Wavoip' do
    sequence(:phone_number) { |n| "+1555#{format('%07d', n)}" }
    device_token { SecureRandom.hex(32) }
    account

    after(:create) do |channel_wavoip|
      create(:inbox, channel: channel_wavoip, account: channel_wavoip.account)
    end
  end
end
