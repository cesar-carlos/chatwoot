# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::StatusMapper do
  subject(:mapper) { described_class.new }

  describe '#to_call_status' do
    {
      'INCOMING_RING' => 'ringing',
      'OUTGOING_RING' => 'ringing',
      'OUTGOING_CALLING' => 'ringing',
      'CALLING' => 'ringing',
      'CONNECTING' => 'ringing',
      'ACTIVE' => 'in_progress',
      'ENDED' => 'completed',
      'HANDLED_REMOTELY' => 'completed',
      'NOT_ANSWERED' => 'no_answer',
      'REJECTED' => 'failed',
      'FAILED' => 'failed',
      'CONNECTION_LOST' => 'failed',
      'REMOTE_CALL_IN_PROGRESS' => nil,
      'DISCONNECTED' => nil
    }.each do |external_status, expected|
      it "maps #{external_status} to #{expected.inspect}" do
        expect(mapper.to_call_status(external_status)).to eq(expected)
      end
    end

    it 'returns nil for blank status' do
      expect(mapper.to_call_status(nil)).to be_nil
    end
  end

  describe '#terminal?' do
    it 'returns true for completed, no_answer, and failed' do
      aggregate_failures do
        expect(mapper.terminal?('completed')).to be(true)
        expect(mapper.terminal?('no_answer')).to be(true)
        expect(mapper.terminal?('failed')).to be(true)
      end
    end

    it 'returns false for ringing and in_progress' do
      aggregate_failures do
        expect(mapper.terminal?('ringing')).to be(false)
        expect(mapper.terminal?('in_progress')).to be(false)
      end
    end
  end

  describe '#end_reason_for' do
    {
      'HANDLED_REMOTELY' => 'handled_remotely',
      'REJECTED' => 'rejected',
      'FAILED' => 'failed',
      'CONNECTION_LOST' => 'failed',
      'NOT_ANSWERED' => 'no_answer',
      'ENDED' => nil
    }.each do |external_status, expected|
      it "maps #{external_status} end reason to #{expected.inspect}" do
        expect(mapper.end_reason_for(external_status)).to eq(expected)
      end
    end
  end
end
