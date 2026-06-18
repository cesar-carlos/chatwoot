require 'rails_helper'

RSpec.describe Whatsapp::ContactMessagePayloadBuilder do
  let(:message) { build(:message) }
  let(:attachment) do
    message.attachments.build(
      file_type: :contact,
      fallback_title: '+918660944581',
      meta: { 'firstName' => 'Jane', 'lastName' => 'Doe' }
    )
  end

  describe '.build' do
    it 'builds contacts type structure with name and phones' do
      result = described_class.build(attachment)

      expect(result).to eq(
        name: {
          formatted_name: 'Jane Doe',
          first_name: 'Jane',
          last_name: 'Doe'
        },
        phones: [{ phone: '+918660944581', type: 'CELL' }]
      )
    end

    context 'when meta uses snake_case keys' do
      let(:attachment) do
        message.attachments.build(
          file_type: :contact,
          fallback_title: '+918660944581',
          meta: { 'first_name' => 'Jane', 'last_name' => 'Doe' }
        )
      end

      it 'reads name fields from snake_case meta' do
        result = described_class.build(attachment)

        expect(result[:name]).to include(
          formatted_name: 'Jane Doe',
          first_name: 'Jane',
          last_name: 'Doe'
        )
      end
    end

    context 'when name is missing' do
      let(:attachment) do
        message.attachments.build(
          file_type: :contact,
          fallback_title: '+918660944581',
          meta: {}
        )
      end

      it 'uses the phone number as formatted_name' do
        result = described_class.build(attachment)

        expect(result[:name][:formatted_name]).to eq('+918660944581')
        expect(result[:phones]).to eq([{ phone: '+918660944581', type: 'CELL' }])
      end
    end
  end
end
