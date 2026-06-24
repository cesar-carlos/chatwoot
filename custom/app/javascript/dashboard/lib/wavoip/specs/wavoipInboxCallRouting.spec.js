import { describe, expect, it } from 'vitest';
import { shouldAgentReceiveWavoipCalls } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';

describe('shouldAgentReceiveWavoipCalls', () => {
  it('allows inbox members regardless of administrator role', () => {
    expect(
      shouldAgentReceiveWavoipCalls(
        {
          current_user_inbox_member: true,
          incoming_call_include_administrators: false,
        },
        { isAdministrator: true }
      )
    ).toBe(true);
  });

  it('blocks non-member agents', () => {
    expect(
      shouldAgentReceiveWavoipCalls(
        {
          current_user_inbox_member: false,
          incoming_call_include_administrators: true,
        },
        { isAdministrator: false }
      )
    ).toBe(false);
  });

  it('allows administrators when include flag is enabled', () => {
    expect(
      shouldAgentReceiveWavoipCalls(
        {
          current_user_inbox_member: false,
          incoming_call_include_administrators: true,
        },
        { isAdministrator: true }
      )
    ).toBe(true);
  });

  it('blocks administrators when include flag is disabled', () => {
    expect(
      shouldAgentReceiveWavoipCalls(
        {
          current_user_inbox_member: false,
          incoming_call_include_administrators: false,
        },
        { isAdministrator: true }
      )
    ).toBe(false);
  });
});
