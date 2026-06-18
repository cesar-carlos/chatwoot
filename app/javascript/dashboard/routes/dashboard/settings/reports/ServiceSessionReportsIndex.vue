<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { formatTime } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import ServiceSessionEntityFilter from './components/ServiceSessionEntityFilter.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ServiceSessionReportsAPI from 'dashboard/api/serviceSessionReports';
import {
  downloadCsvFile,
  generateFileName,
} from 'dashboard/helper/downloadHelper';
import {
  generateServiceSessionListURLParams,
  parseServiceSessionListURLParams,
} from './helpers/reportFilterHelper';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const LIST_PER_PAGE = 25;

const isLoading = ref(false);
const summary = ref(null);
const tabData = ref({});
const listPage = ref(parseServiceSessionListURLParams(route.query).page);
const filters = ref({
  since: null,
  until: null,
  businessHours: false,
  inboxId: null,
  teamId: null,
  userIds: null,
  labelIds: null,
});
const activeTab = ref('summary');

const tabs = computed(() => [
  { id: 'summary', label: t('SERVICE_SESSION_REPORTS.TABS.SUMMARY') },
  { id: 'open', label: t('SERVICE_SESSION_REPORTS.TABS.OPEN') },
  { id: 'closed', label: t('SERVICE_SESSION_REPORTS.TABS.CLOSED') },
  { id: 'byAgent', label: t('SERVICE_SESSION_REPORTS.TABS.BY_AGENT') },
  { id: 'byInbox', label: t('SERVICE_SESSION_REPORTS.TABS.BY_INBOX') },
  { id: 'byTeam', label: t('SERVICE_SESSION_REPORTS.TABS.BY_TEAM') },
  { id: 'byLabel', label: t('SERVICE_SESSION_REPORTS.TABS.BY_LABEL') },
]);

const tabFetchers = {
  summary: 'summary',
  open: 'open',
  closed: 'closed',
  byAgent: 'byAgent',
  byInbox: 'byInbox',
  byTeam: 'byTeam',
  byLabel: 'byLabel',
};

const isListTab = tabId => tabId === 'open' || tabId === 'closed';

const formatCount = value =>
  Number.isFinite(value)
    ? Number(value).toLocaleString()
    : t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE');
const formatSeconds = value =>
  Number.isFinite(value)
    ? formatTime(value)
    : t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE');
const formatPercent = value =>
  Number.isFinite(value)
    ? `${(Number(value) * 100).toFixed(2)}%`
    : t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE');

const activeData = computed(() => tabData.value[activeTab.value] || null);
const listPagination = computed(() => {
  const data = activeData.value;
  if (!data || !isListTab(activeTab.value)) return null;

  return {
    currentPage: data.page || listPage.value,
    totalItems: data.total_count || 0,
    itemsPerPage: data.per_page || LIST_PER_PAGE,
  };
});

const summaryCards = computed(() => {
  const value = summary.value || {};
  return [
    {
      key: 'open',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS'),
      value: formatCount(value.open_sessions_count),
    },
    {
      key: 'closed',
      label: t('SERVICE_SESSION_REPORTS.METRICS.CLOSED_SESSIONS'),
      value: formatCount(value.closed_sessions_count),
    },
    {
      key: 'total',
      label: t('SERVICE_SESSION_REPORTS.METRICS.TOTAL_SESSIONS'),
      hint: t('SERVICE_SESSION_REPORTS.METRICS.TOTAL_SESSIONS_HINT'),
      value: formatCount(value.total_sessions),
    },
    {
      key: 'avgDuration',
      label: t('SERVICE_SESSION_REPORTS.METRICS.AVG_SESSION_DURATION'),
      value: formatSeconds(value.avg_session_duration),
    },
    {
      key: 'avgFirstResponse',
      label: t('SERVICE_SESSION_REPORTS.METRICS.AVG_FIRST_RESPONSE_TIME'),
      value: formatSeconds(value.avg_first_response_time),
    },
    {
      key: 'reopenRate',
      label: t('SERVICE_SESSION_REPORTS.METRICS.REOPEN_RATE'),
      value: formatPercent(value.reopen_rate),
    },
    {
      key: 'p95FirstResponse',
      label: t('SERVICE_SESSION_REPORTS.METRICS.P95_FIRST_RESPONSE_TIME'),
      value: formatSeconds(value.p95_first_response_time),
    },
    {
      key: 'p95Resolution',
      label: t('SERVICE_SESSION_REPORTS.METRICS.P95_SESSION_RESOLUTION_TIME'),
      value: formatSeconds(value.p95_session_resolution_time),
    },
    {
      key: 'openAvgAge',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS_AVG_AGE'),
      value: formatSeconds(value.open_sessions_avg_age_seconds),
    },
    {
      key: 'openP95Age',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS_P95_AGE'),
      value: formatSeconds(value.open_sessions_p95_age_seconds),
    },
    {
      key: 'openOver24h',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS_OVER_24H'),
      value: formatCount(value.open_sessions_aging_buckets?.over_24h),
    },
    {
      key: 'openOver72h',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS_OVER_72H'),
      value: formatCount(value.open_sessions_aging_buckets?.over_72h),
    },
    {
      key: 'openOver7d',
      label: t('SERVICE_SESSION_REPORTS.METRICS.OPEN_SESSIONS_OVER_7D'),
      value: formatCount(value.open_sessions_aging_buckets?.over_7d),
    },
  ];
});

const openRows = computed(() => activeData.value?.sessions || []);
const closedRows = computed(() => activeData.value?.sessions || []);
const groupedRows = computed(() =>
  Array.isArray(activeData.value) ? activeData.value : []
);

const updateListPageURL = page => {
  const pageParams = generateServiceSessionListURLParams({ page });
  const nextQuery = { ...route.query };

  if (pageParams.page) {
    nextQuery.page = pageParams.page;
  } else {
    delete nextQuery.page;
  }

  router.replace({ query: nextQuery });
};

const resetListPage = () => {
  listPage.value = 1;
  updateListPageURL(1);
};

function buildRequestParams(tabId) {
  const params = { ...filters.value };
  if (isListTab(tabId)) {
    params.page = listPage.value;
    params.perPage = LIST_PER_PAGE;
  }
  return params;
}

async function fetchDataForTab(tabId, force = false) {
  const method = tabFetchers[tabId];
  if (!method) return;
  if (!force && tabData.value[tabId] && tabId !== 'summary') return;

  isLoading.value = true;
  try {
    const { data } = await ServiceSessionReportsAPI[method](
      buildRequestParams(tabId)
    );
    if (tabId === 'summary') {
      summary.value = data;
    } else {
      tabData.value = { ...tabData.value, [tabId]: data };
    }
  } catch {
    useAlert(t('SERVICE_SESSION_REPORTS.ERRORS.FETCH_FAILED'));
  } finally {
    isLoading.value = false;
  }
}

async function onFilterChange({ from, to, businessHours }) {
  filters.value = {
    ...filters.value,
    since: from,
    until: to,
    businessHours,
  };
  resetListPage();
  tabData.value = {};
  await fetchDataForTab(activeTab.value, true);
}

async function onEntityFilterChange(entityFilters) {
  filters.value = {
    ...filters.value,
    inboxId: entityFilters.inbox_id,
    teamId: entityFilters.team_id,
    userIds: entityFilters.user_ids,
    labelIds: entityFilters.label_ids,
  };
  resetListPage();
  tabData.value = {};
  await fetchDataForTab(activeTab.value, true);
}

async function setTab(tabId) {
  activeTab.value = tabId;
  if (isListTab(tabId)) {
    listPage.value = parseServiceSessionListURLParams(route.query).page;
  } else {
    updateListPageURL(1);
  }
  await fetchDataForTab(tabId, isListTab(tabId));
}

async function onListPageChange(page) {
  listPage.value = page;
  updateListPageURL(page);
  await fetchDataForTab(activeTab.value, true);
}

const formatName = row => {
  if (row?.id === 0) {
    return t('SERVICE_SESSION_REPORTS.COMMON.UNASSIGNED_TEAM');
  }

  return (
    row?.name || row?.title || t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE')
  );
};

const formatUnixTime = value =>
  Number.isFinite(value)
    ? new Date(value * 1000).toLocaleString()
    : t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE');

const formatSessionDuration = row => formatSeconds(row.session_duration);

const escapeCsvValue = value => {
  const stringValue = value == null ? '' : String(value);
  if (/[",\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }
  return stringValue;
};

const csvRowsForActiveTab = () => {
  if (activeTab.value === 'open') {
    return openRows.value.map(row => [
      formatName(row.contact),
      formatName(row.assignee),
      formatName(row.inbox),
      row.status || t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE'),
      formatUnixTime(row.session_started_at),
    ]);
  }

  if (activeTab.value === 'closed') {
    return closedRows.value.map(row => [
      formatName(row.contact),
      formatName(row.assignee),
      formatName(row.inbox),
      formatSessionDuration(row),
      formatUnixTime(row.resolved_at),
    ]);
  }

  if (groupedRows.value.length) {
    return groupedRows.value.map(row => [
      formatName(row),
      formatCount(row.open_sessions_count),
      formatCount(row.closed_sessions_count),
      formatSeconds(row.avg_session_duration),
    ]);
  }

  return [];
};

const csvHeadersForActiveTab = () => {
  if (activeTab.value === 'open') {
    return [
      t('SERVICE_SESSION_REPORTS.TABLE.CONTACT'),
      t('SERVICE_SESSION_REPORTS.TABLE.AGENT'),
      t('SERVICE_SESSION_REPORTS.TABLE.INBOX'),
      t('SERVICE_SESSION_REPORTS.TABLE.STATUS'),
      t('SERVICE_SESSION_REPORTS.TABLE.SESSION_STARTED_AT'),
    ];
  }

  if (activeTab.value === 'closed') {
    return [
      t('SERVICE_SESSION_REPORTS.TABLE.CONTACT'),
      t('SERVICE_SESSION_REPORTS.TABLE.AGENT'),
      t('SERVICE_SESSION_REPORTS.TABLE.INBOX'),
      t('SERVICE_SESSION_REPORTS.TABLE.SESSION_DURATION'),
      t('SERVICE_SESSION_REPORTS.TABLE.RESOLVED_AT'),
    ];
  }

  return [
    t('SERVICE_SESSION_REPORTS.TABLE.NAME'),
    t('SERVICE_SESSION_REPORTS.TABLE.OPEN_SESSIONS'),
    t('SERVICE_SESSION_REPORTS.TABLE.CLOSED_SESSIONS'),
    t('SERVICE_SESSION_REPORTS.TABLE.AVG_SESSION_DURATION'),
  ];
};

const canDownloadCsv = computed(
  () => activeTab.value !== 'summary' && csvRowsForActiveTab().length > 0
);

const downloadReports = () => {
  const rows = csvRowsForActiveTab();
  if (!rows.length) return;

  const csvContent = [csvHeadersForActiveTab(), ...rows]
    .map(row => row.map(escapeCsvValue).join(','))
    .join('\n');
  const tabTypeMap = {
    open: 'service-sessions-open',
    closed: 'service-sessions-closed',
    byAgent: 'service-sessions-agent',
    byInbox: 'service-sessions-inbox',
    byTeam: 'service-sessions-team',
    byLabel: 'service-sessions-label',
  };
  const fileName = generateFileName({
    type: tabTypeMap[activeTab.value] || 'service-sessions',
    to: filters.value.until || Math.floor(Date.now() / 1000),
    businessHours: filters.value.businessHours,
  });

  downloadCsvFile(fileName, csvContent);
};
</script>

<template>
  <ReportHeader
    :header-title="$t('SERVICE_SESSION_REPORTS.HEADER')"
    :header-description="$t('SERVICE_SESSION_REPORTS.DESCRIPTION')"
  >
    <V4Button
      v-if="canDownloadCsv"
      :label="$t('SERVICE_SESSION_REPORTS.DOWNLOAD')"
      icon="i-ph-download-simple"
      size="sm"
      @click="downloadReports"
    />
  </ReportHeader>

  <div class="flex flex-col gap-4">
    <ReportFilters
      :show-entity-filter="false"
      :show-group-by="false"
      show-business-hours
      @filter-change="onFilterChange"
    />

    <ServiceSessionEntityFilter @filter-change="onEntityFilterChange" />

    <div class="flex flex-wrap gap-2">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        class="px-3 py-2 text-sm rounded-lg border"
        :class="
          activeTab === tab.id
            ? 'border-n-brand text-n-brand bg-n-alpha-1'
            : 'border-n-weak text-n-slate-11'
        "
        @click="setTab(tab.id)"
      >
        {{ tab.label }}
      </button>
    </div>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ $t('SERVICE_SESSION_REPORTS.LOADING') }}
    </div>

    <div
      v-else-if="activeTab === 'summary'"
      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3"
    >
      <div
        v-for="card in summaryCards"
        :key="card.key"
        class="rounded-xl border border-n-weak p-4 bg-n-solid-2"
      >
        <p class="text-xs text-n-slate-11 mb-1">
          {{ card.label }}
        </p>
        <p
          v-if="card.hint"
          class="text-[10px] text-n-slate-10 mb-1 leading-tight"
        >
          {{ card.hint }}
        </p>
        <p class="text-xl font-semibold text-n-slate-12">
          {{ card.value }}
        </p>
      </div>
    </div>

    <div
      v-else-if="activeTab === 'open'"
      class="rounded-xl border border-n-weak bg-n-solid-2 overflow-x-auto"
    >
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak">
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.CONTACT') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.AGENT') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.INBOX') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.STATUS') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.SESSION_STARTED_AT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!openRows.length">
            <td class="p-3 text-n-slate-11" colspan="5">
              {{ $t('SERVICE_SESSION_REPORTS.EMPTY_STATE.NO_DATA') }}
            </td>
          </tr>
          <tr
            v-for="row in openRows"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="p-3">{{ formatName(row.contact) }}</td>
            <td class="p-3">{{ formatName(row.assignee) }}</td>
            <td class="p-3">{{ formatName(row.inbox) }}</td>
            <td class="p-3">
              {{
                row.status || $t('SERVICE_SESSION_REPORTS.COMMON.NOT_AVAILABLE')
              }}
            </td>
            <td class="p-3">{{ formatUnixTime(row.session_started_at) }}</td>
          </tr>
        </tbody>
      </table>
      <PaginationFooter
        v-if="listPagination?.totalItems"
        :current-page="listPagination.currentPage"
        :total-items="listPagination.totalItems"
        :items-per-page="listPagination.itemsPerPage"
        @update:current-page="onListPageChange"
      />
    </div>

    <div
      v-else-if="activeTab === 'closed'"
      class="rounded-xl border border-n-weak bg-n-solid-2 overflow-x-auto"
    >
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak">
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.CONTACT') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.AGENT') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.INBOX') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.SESSION_DURATION') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.RESOLVED_AT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!closedRows.length">
            <td class="p-3 text-n-slate-11" colspan="5">
              {{ $t('SERVICE_SESSION_REPORTS.EMPTY_STATE.NO_DATA') }}
            </td>
          </tr>
          <tr
            v-for="row in closedRows"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="p-3">{{ formatName(row.contact) }}</td>
            <td class="p-3">{{ formatName(row.assignee) }}</td>
            <td class="p-3">{{ formatName(row.inbox) }}</td>
            <td class="p-3">{{ formatSessionDuration(row) }}</td>
            <td class="p-3">{{ formatUnixTime(row.resolved_at) }}</td>
          </tr>
        </tbody>
      </table>
      <PaginationFooter
        v-if="listPagination?.totalItems"
        :current-page="listPagination.currentPage"
        :total-items="listPagination.totalItems"
        :items-per-page="listPagination.itemsPerPage"
        @update:current-page="onListPageChange"
      />
    </div>

    <div
      v-else
      class="rounded-xl border border-n-weak bg-n-solid-2 overflow-x-auto"
    >
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak">
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.NAME') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.OPEN_SESSIONS') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.CLOSED_SESSIONS') }}
            </th>
            <th class="p-3">
              {{ $t('SERVICE_SESSION_REPORTS.TABLE.AVG_SESSION_DURATION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!groupedRows.length">
            <td class="p-3 text-n-slate-11" colspan="4">
              {{ $t('SERVICE_SESSION_REPORTS.EMPTY_STATE.NO_DATA') }}
            </td>
          </tr>
          <tr
            v-for="row in groupedRows"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="p-3">{{ formatName(row) }}</td>
            <td class="p-3">{{ formatCount(row.open_sessions_count) }}</td>
            <td class="p-3">{{ formatCount(row.closed_sessions_count) }}</td>
            <td class="p-3">{{ formatSeconds(row.avg_session_duration) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
