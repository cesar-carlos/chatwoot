import { frontendURL } from 'dashboard/helper/URLHelper';
import InboxListView from './InboxList.vue';
import InboxDetailView from './InboxView.vue';
import InboxEmptyStateView from './InboxEmptyState.vue';
import { INBOX_VIEW_ROUTE_PERMISSIONS } from 'dashboard/constants/permissions.js';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/inbox-view'),
    component: InboxListView,
    children: [
      {
        path: '',
        name: 'inbox_view',
        component: InboxEmptyStateView,
        meta: {
          // FORK: custom role inbox view permission
          permissions: INBOX_VIEW_ROUTE_PERMISSIONS,
        },
      },
      {
        path: ':type/:id',
        name: 'inbox_view_conversation',
        component: InboxDetailView,
        meta: {
          // FORK: custom role inbox view permission
          permissions: INBOX_VIEW_ROUTE_PERMISSIONS,
        },
      },
    ],
  },
];
