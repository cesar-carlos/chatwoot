import { unsubscribePush } from 'customDashboard/helper/pushHelper';

export const logoutWithPushCleanup = async (url, clearCookiesOnLogout) => {
  // A failed service worker must not trap the user in the current session.
  try {
    const result = await unsubscribePush();
    if (result.serverError) {
      // eslint-disable-next-line no-console
      console.error('Browser push cleanup failed on the server during logout');
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Browser push cleanup failed during logout');
  }

  const response = await window.axios.delete(url);
  await clearCookiesOnLogout();
  return response;
};
