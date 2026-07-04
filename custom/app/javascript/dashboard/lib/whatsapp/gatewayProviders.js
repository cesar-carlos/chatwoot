export const GATEWAY_WHATSAPP_PROVIDERS = ['evolution', 'evolution_go'];

export function isGatewayWhatsAppProvider(provider) {
  return GATEWAY_WHATSAPP_PROVIDERS.includes(provider);
}

export function isGatewayWhatsAppInbox(inbox) {
  if (!inbox) return false;
  const type = inbox.channel_type || inbox.channelType;
  const provider = inbox.provider;
  return type === 'Channel::Whatsapp' && isGatewayWhatsAppProvider(provider);
}
