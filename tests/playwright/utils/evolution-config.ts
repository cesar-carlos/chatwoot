export const evolutionConfig = {
  baseUrl: process.env.EVOLUTION_BASE_URL || '',
  apiKey: process.env.EVOLUTION_API_KEY || '',
  accountId: process.env.ACCOUNT_ID || '8',
};

export function hasEvolutionCredentials() {
  return Boolean(evolutionConfig.baseUrl && evolutionConfig.apiKey);
}
