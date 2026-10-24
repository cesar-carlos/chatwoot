import helpUrls from '../../../../config/feature_help_urls.yml';

// FORK: conversation rules have no public help URL yet
const helpUrlMap = {
  ...helpUrls,
  conversation_rules: '',
};

export function getHelpUrlForFeature(featureName) {
  return helpUrlMap[featureName];
}
