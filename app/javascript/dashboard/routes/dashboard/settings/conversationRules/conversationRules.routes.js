import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import ConversationRulesIndex from './index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/conversation-rules'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'conversation_rules_index',
          component: ConversationRulesIndex,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
