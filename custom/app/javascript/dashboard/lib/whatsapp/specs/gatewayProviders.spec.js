import { describe, expect, it } from 'vitest';
import {
  GATEWAY_WHATSAPP_PROVIDERS,
  isGatewayWhatsAppInbox,
  isGatewayWhatsAppProvider,
} from '../gatewayProviders';

describe('gatewayProviders', () => {
  it('lists evolution and evolution_go as gateway providers', () => {
    expect(GATEWAY_WHATSAPP_PROVIDERS).toEqual(['evolution', 'evolution_go']);
  });

  it('detects gateway providers by key', () => {
    expect(isGatewayWhatsAppProvider('evolution')).toBe(true);
    expect(isGatewayWhatsAppProvider('evolution_go')).toBe(true);
    expect(isGatewayWhatsAppProvider('whatsapp_cloud')).toBe(false);
  });

  it('detects gateway WhatsApp inboxes', () => {
    expect(
      isGatewayWhatsAppInbox({
        channel_type: 'Channel::Whatsapp',
        provider: 'evolution_go',
      })
    ).toBe(true);
    expect(
      isGatewayWhatsAppInbox({
        channelType: 'Channel::Whatsapp',
        provider: 'evolution',
      })
    ).toBe(true);
    expect(
      isGatewayWhatsAppInbox({
        channel_type: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
      })
    ).toBe(false);
  });
});
