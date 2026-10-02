export const getPushPermissionHelpPlatform = () => {
  const agent = navigator.userAgent;
  if (
    /iPad|iPhone|iPod/.test(agent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  )
    return 'IOS';
  if (/Android/.test(agent)) return 'ANDROID';
  if (/Edg\//.test(agent)) return 'EDGE';
  if (/Chrome\//.test(agent)) return 'CHROME';
  return 'GENERIC';
};
