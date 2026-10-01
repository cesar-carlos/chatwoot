export const loadNotificationPreferences = async context => {
  const accountId = context.accountId;
  context.preferencesLoadId += 1;
  const id = context.preferencesLoadId;
  context.preferencesLoadedAccount = null;
  context.preferencesLoadError = false;
  try {
    await context.$store.dispatch('userNotificationSettings/get', accountId);
    if (
      id === context.preferencesLoadId &&
      String(accountId) === String(context.accountId)
    ) {
      context.preferencesLoadedAccount = String(accountId);
    }
  } catch (error) {
    if (id === context.preferencesLoadId) context.preferencesLoadError = true;
  }
};
