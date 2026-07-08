# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::DirectionInferrer do
  subject(:result) do
    described_class.new(
      payload: payload.with_indifferent_access,
      webhook_action: webhook_action,
      external_call_id: 'test_call_id'
    ).send(:infer)
  end

  let(:webhook_action) { :create }

  context 'when direction is explicit INCOMING and endpoints do not disagree' do
    let(:payload) do
      { 'direction' => 'INCOMING', 'phone' => '+5511999999999', 'caller' => '+5511888888888' }
    end

    it { is_expected.to eq(:incoming) }
  end

  context 'when direction is OUTCOMING' do
    let(:payload) { { 'direction' => 'OUTCOMING' } }

    it { is_expected.to eq(:outgoing) }
  end

  context 'when inbox is the caller even if direction says INCOMING' do
    let(:payload) do
      {
        'direction' => 'INCOMING',
        'phone' => '5566999050312',
        'caller' => '5566999050312',
        'receiver' => '556697193168'
      }
    end

    it { is_expected.to eq(:outgoing) }
  end

  context 'when direction is absent but caller/receiver imply incoming' do
    let(:payload) do
      {
        'phone' => '5566999050312',
        'caller' => '5511888888888',
        'receiver' => '5566999050312'
      }
    end

    it { is_expected.to eq(:incoming) }
  end

  context 'when direction must be inferred from status' do
    it 'maps OUTGOING_RING to outgoing' do
      expect(
        described_class.new(
          payload: { 'status' => 'OUTGOING_RING' }.with_indifferent_access,
          webhook_action: :create,
          external_call_id: 'test_call_id'
        ).send(:infer)
      ).to eq(:outgoing)
    end

    it 'maps INCOMING_RING to incoming' do
      expect(
        described_class.new(
          payload: { 'status' => 'INCOMING_RING' }.with_indifferent_access,
          webhook_action: :create,
          external_call_id: 'test_call_id'
        ).send(:infer)
      ).to eq(:incoming)
    end
  end

  context 'when no signal is available' do
    let(:payload) { { 'status' => 'ACTIVE' } }

    it { is_expected.to be_nil }
  end

  describe 'logging' do
    let(:payload) { { 'status' => 'ACTIVE' } }

    it 'warns only on CREATE with a fully blank direction' do
      allow(Rails.env).to receive(:production?).and_return(false)
      allow(Rails.logger).to receive(:warn)

      result

      expect(Rails.logger).to have_received(:warn).with(/CALL CREATE missing direction/)
    end

    context 'when webhook action is UPDATE' do
      let(:webhook_action) { :update }

      it 'does not log even when direction is blank' do
        allow(Rails.logger).to receive(:warn)

        result

        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end
end
