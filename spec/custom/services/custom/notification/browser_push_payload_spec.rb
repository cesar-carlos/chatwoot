require 'rails_helper'

RSpec.describe Custom::Notification::BrowserPushPayload do
  let(:message) do
    {
      title: 'New message', body: 'Hello', url: '/app/accounts/1/conversations/2',
      user_id: 3, account_id: 1, notification_id: 4, tag: 'message_2_4',
      action_labels: { open: 'Open conversation', read: 'Mark as read' }
    }
  end

  it 'preserves ordinary content, routing and recipient identity without mutating its input' do
    expect(JSON.parse(described_class.generate(message))).to eq(JSON.parse(JSON.generate(message)))
    expect(message[:body]).to eq('Hello')
  end

  it 'bounds long URLs, multibyte text and JSON escapes by final encoded bytes' do
    ["https://example.test/#{'x' * 5000}", '😀á' * 5000, "\"\n\\" * 5000].each do |body|
      json = described_class.generate(message.merge(body: body))
      payload = JSON.parse(json)
      expect(json.bytesize).to be <= described_class::MAX_JSON_BYTES
      expect(payload['body']).to end_with('…')
      expect(payload['body']).to be_valid_encoding
      expect(payload).to include('url' => message[:url], 'notification_id' => 4, 'user_id' => 3, 'account_id' => 1)
      expect(payload['action_labels']).to eq('open' => 'Open conversation', 'read' => 'Mark as read')
    end
  end

  it 'fits the encrypted web-push request within 4096 bytes' do
    keys = WebPush.generate_key
    request = WebPush::Request.new(
      message: described_class.generate(message.merge(body: '😀' * 5000)),
      subscription: { endpoint: 'https://web.push.apple.com/device', keys: { p256dh: keys.public_key, auth: Base64.urlsafe_encode64('a' * 16) } },
      vapid: {}
    )
    expect(request.body.bytesize).to be <= 4096
  end

  it 'bounds long titles and preserves Unicode' do
    payload = JSON.parse(described_class.generate(message.merge(title: '😀' * 5000)))
    expect(payload['title'].length).to be <= described_class::MAX_TITLE_LENGTH
    expect(payload['title']).to be_valid_encoding
  end

  it 'reports oversized configuration rather than truncating the conversation URL or identity' do
    expect { described_class.generate(message.merge(url: "https://example.test/#{'x' * 5000}")) }
      .to raise_error(ArgumentError, 'Browser push metadata exceeds the payload limit')
  end
end
