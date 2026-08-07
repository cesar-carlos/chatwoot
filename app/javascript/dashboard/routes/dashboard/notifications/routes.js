/* eslint arrow-body-style: 0 */
import { frontendURL } from '../../../helper/URLHelper';
import SettingsWrapper from '../settings/SettingsWrapper.vue';
import NotificationsView from './components/NotificationsView.vue';
import { INBOX_VIEW_ROUTE_PERMISSIONS } from 'dashboard/constants/permissions.js';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/notifications'),
    component: SettingsWrapper,
    children: [
      {
        path: '',
        name: 'notifications_index',
        component: NotificationsView,
        meta: {
          // FORK: custom role inbox view permission — align with Inbox View gate
          permissions: INBOX_VIEW_ROUTE_PERMISSIONS,
        },
      },
    ],
  },
];
