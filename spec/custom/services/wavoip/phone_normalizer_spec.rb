# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::PhoneNormalizer do
  let(:brazil_inbox_phone) { '+556697193168' }

  it 'keeps E.164 numbers unchanged' do
    expect(described_class.normalize('+55669999050312')).to eq('+55669999050312')
  end

  it 'prefixes country code for full digits without plus' do
    expect(described_class.normalize('55669999050312')).to eq('+55669999050312')
  end

  it 'infers +55 for 11-digit BR mobiles when inbox is Brazilian' do
    expect(
      described_class.normalize('66999050312', inbox_phone: brazil_inbox_phone)
    ).to eq('+5566999050312')
  end

  it 'does not prefix +55 for US numbers on a Brazilian inbox' do
    # 310 is valid NANP (LA) but invalid as a BR national number.
    expect(
      described_class.normalize('3105551234', inbox_phone: brazil_inbox_phone)
    ).to eq('+13105551234')
  end

  it 'prefers BR landline parse over NANP false positive on a Brazilian inbox' do
    # Rio DDD 21 + 8-digit landline looks NANP-shaped (area 213) but is valid BR.
    expect(
      described_class.normalize('2133334444', inbox_phone: brazil_inbox_phone)
    ).to eq('+552133334444')
  end

  it 'parses Argentina mobile without plus when digits include country code' do
    expect(described_class.normalize('5491145678901')).to eq('+5491145678901')
  end

  it 'parses Mexico mobile without plus when digits include country code' do
    expect(described_class.normalize('5215512345678')).to eq('+5215512345678')
  end

  it 'parses Chile mobile without plus when digits include country code' do
    expect(described_class.normalize('56912345678')).to eq('+56912345678')
  end

  it 'parses Argentina local mobile using inbox country hint' do
    expect(
      described_class.normalize('91145678901', inbox_phone: '+5491140000000')
    ).to eq('+5491145678901')
  end

  it 'parses Mexico local mobile using inbox country hint' do
    expect(
      described_class.normalize('5512345678', inbox_phone: '+525512345678')
    ).to eq('+525512345678')
  end

  it 'parses Colombia mobile without plus when digits include country code' do
    expect(described_class.normalize('573001234567')).to eq('+573001234567')
  end

  it 'does not infer +55 when inbox is not Brazilian' do
    expect(
      described_class.normalize('66999050312', inbox_phone: '+14155551234')
    ).to eq('+66999050312')
  end
end
