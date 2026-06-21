export const evolutionConfig = {
  baseUrl: process.env.EVOLUTION_BASE_URL || '',
  apiKey: process.env.EVOLUTION_API_KEY || '',
  accountId: process.env.ACCOUNT_ID || '8',
};

const PLACEHOLDER_EVOLUTION_API_KEYS = new Set([
  'your-evolution-authentication-api-key',
]);

export function hasEvolutionCredentials() {
  const baseUrl = evolutionConfig.baseUrl.trim();
  const apiKey = evolutionConfig.apiKey.trim();

  if (!baseUrl || !apiKey) return false;
  if (PLACEHOLDER_EVOLUTION_API_KEYS.has(apiKey)) return false;

  return true;
}
