import { test } from '@playwright/test';

/**
 * Pilot gate checklist (doc/feature/whatsapp-voice/wavoip-provider/operations-runbook.md).
 * Most gates need live Wavoip/Meta credentials — run manually in staging.
 */
test.describe('WhatsApp Voice pilot gates', () => {
  test('W1 — live Wavoip CALL webhook (ops)', async () => {
    test.skip(
      !process.env.WAVOIP_PILOT_W1_VERIFIED,
      'Ops: confirm Wavoip panel webhook URL + grep nginx/Sidekiq logs; set WAVOIP_PILOT_W1_VERIFIED=1'
    );
  });

  test('G0.4 — multi-tab acceptedElsewhere (manual)', async () => {
    test.skip(
      !process.env.WAVOIP_PILOT_G04_VERIFIED,
      'Manual: two browser tabs same agent; accept in one → other shows acceptedElsewhere'
    );
  });

  test('O1 — outbound bidirectional audio (manual)', async () => {
    test.skip(
      !process.env.WAVOIP_PILOT_O1_VERIFIED,
      'Manual: outbound call with contact answer + two-way audio'
    );
  });
});
