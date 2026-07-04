# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::DirectionInferrer do
  def infer(payload, webhook_action: :create)
    described_class.new(
      payload: payload.with_indifferent_access,
      webhook_action: webhook_action,
      external_call_id: 'test_call_id'
    ).infer
  end

  it 'uses the explicit INCOMING direction when endpoints do not disagree' do
    expect(infer('direction' => 'INCOMING', 'phone' => '+5511999999999', 'caller' => '+5511888888888')).to eq(:incoming)
  end

  it 'maps OUTCOMING defensively to :outgoing' do
    expect(infer('direction' => 'OUTCOMING')).to eq(:outgoing)
  end

  it 'treats the inbox being the caller as outgoing even if direction says INCOMING' do
    expect(
      infer(
        'direction' => 'INCOMING',
        'phone' => '5566999050312',
        'caller' => '5566999050312',
        'receiver' => '556697193168'
      )
    ).to eq(:outgoing)
  end

  it 'infers from caller/receiver when direction is absent' do
    expect(
      infer(
        'phone' => '5566999050312',
        'caller' => '5511888888888',
        'receiver' => '5566999050312'
      )
    ).to eq(:incoming)
  end

  it 'falls back to status-based inference when nothing else resolves' do
    expect(infer('status' => 'OUTGOING_RING')).to eq(:outgoing)
    expect(infer('status' => 'INCOMING_RING')).to eq(:incoming)
  end

  it 'returns nil when no signal is available' do
    expect(infer('status' => 'ACTIVE')).to be_nil
  end

  it 'logs a warning only on CREATE with a fully blank direction' do
    allow(Rails.env).to receive(:production?).and_return(false)
    allow(Rails.logger).to receive(:warn)

    infer({ 'status' => 'ACTIVE' }, webhook_action: :create)

    expect(Rails.logger).to have_received(:warn).with(/CALL CREATE missing direction/)
  end

  it 'does not log on UPDATE even when direction is blank' do
    allow(Rails.logger).to receive(:warn)

    infer({ 'status' => 'ACTIVE' }, webhook_action: :update)

    expect(Rails.logger).not_to have_received(:warn)
  end
end
