import { describe, expect, it, vi } from 'vitest';
import { onEvolutionGoConnectionClosed } from 'customDashboard/lib/evolution_go/evolutionGoCableRegistry';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/i18n', () => ({
  default: {
    global: {
      t: vi.fn((key, params) => `${key}:${params?.inbox || ''}`),
    },
  },
}));

describe('evolutionGoCableRegistry', () => {
  it('shows disconnect alert for evolution go connection_closed events', async () => {
    const { useAlert } = await import('dashboard/composables');

    onEvolutionGoConnectionClosed({ inbox_name: 'Support' });

    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.DISCONNECTED_ALERT:Support'
    );
  });
});
