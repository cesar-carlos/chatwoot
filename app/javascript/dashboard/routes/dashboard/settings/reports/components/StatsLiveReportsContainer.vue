<script setup>
import { computed, onMounted, ref } from 'vue';
import { OVERVIEW_METRICS } from '../constants';
import { useToggle } from '@vueuse/core';

import MetricCard from './overview/MetricCard.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const uiFlags = useMapGetter('getOverviewUIFlags');
const agentStatus = useMapGetter('agents/getAgentStatus');
const accountConversationMetric = useMapGetter('getAccountConversationMetric');
const store = useStore();

const accounti18nKey = 'OVERVIEW_REPORTS.ACCOUNT_CONVERSATIONS';
const teams = useMapGetter('teams/getTeams');

const teamMenuList = computed(() => {
  return [
    { label: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.ALL_TEAMS'), value: null },
    ...teams.value.map(team => ({ label: team.name, value: team.id })),
  ];
});

const agentStatusMetrics = computed(() => {
  let metric = {};
  Object.keys(agentStatus.value).forEach(key => {
    const metricName = t(
      `OVERVIEW_REPORTS.AGENT_STATUS.${OVERVIEW_METRICS[key]}`
    );
    metric[metricName] = agentStatus.value[key];
  });
  return metric;
});
const conversationMetrics = computed(() => {
  let metric = {};
  Object.keys(accountConversationMetric.value).forEach(key => {
    // FORK: opened_by is a breakdown, rendered in its own card
    if (key === 'opened_by') return;
    const metricName = t(`${accounti18nKey}.${OVERVIEW_METRICS[key]}`);
    metric[metricName] = accountConversationMetric.value[key];
  });
  return metric;
});
const openedByMetrics = computed(() => {
  const counts = accountConversationMetric.value?.opened_by || {};
  return {
    [t(`${accounti18nKey}.OPENED_BY_CONTACT`)]: counts.contact || 0,
    [t(`${accounti18nKey}.OPENED_BY_AGENT`)]: counts.agent || 0,
    [t(`${accounti18nKey}.OPENED_BY_PHONE`)]: counts.phone || 0,
    [t(`${accounti18nKey}.OPENED_BY_UNSET`)]: counts.unset || 0,
  };
});

const selectedTeam = ref(null);
const selectedTeamLabel = computed(() => {
  const team =
    teamMenuList.value.find(
      menuItem => menuItem.value === selectedTeam.value
    ) || {};
  return team.label;
});
const fetchData = () => {
  const params = {};
  if (selectedTeam.value) {
    params.team_id = selectedTeam.value;
  }
  store.dispatch('fetchAccountConversationMetric', params);
};

const { startRefetching } = useLiveRefresh(fetchData);
const [showDropdown, toggleDropdown] = useToggle();

const handleAction = ({ value }) => {
  toggleDropdown(false);
  selectedTeam.value = value;
  fetchData();
};

onMounted(() => {
  fetchData();
  startRefetching();
});
</script>

<template>
  <div class="flex flex-col items-center md:flex-row md:flex-wrap gap-4">
    <div
      class="flex-1 w-full max-w-full md:w-[65%] md:max-w-[65%] conversation-metric"
    >
      <MetricCard
        :header="t(`${accounti18nKey}.HEADER`)"
        :is-loading="uiFlags.isFetchingAccountConversationMetric"
        :loading-message="t(`${accounti18nKey}.LOADING_MESSAGE`)"
      >
        <template v-if="teams.length" #control>
          <div
            v-on-clickaway="() => toggleDropdown(false)"
            class="relative flex items-center group z-50"
          >
            <Button
              sm
              slate
              faded
              :label="selectedTeamLabel"
              class="capitalize rounded-md group-hover:bg-n-alpha-2"
              @click="toggleDropdown()"
            />
            <DropdownMenu
              v-if="showDropdown"
              :menu-items="teamMenuList"
              class="mt-1 ltr:right-0 rtl:left-0 xl:ltr:right-0 xl:rtl:left-0 top-full"
              label-class="capitalize"
              @action="handleAction($event)"
            />
          </div>
        </template>
        <div
          v-for="(metric, name, index) in conversationMetrics"
          :key="index"
          class="flex-1 min-w-0 pb-2"
        >
          <h3 class="text-base text-n-slate-11">
            {{ name }}
          </h3>
          <p class="text-n-slate-12 text-3xl mb-0 mt-1">
            {{ metric }}
          </p>
        </div>
      </MetricCard>
    </div>
    <div class="flex-1 w-full max-w-full md:w-[35%] md:max-w-[35%]">
      <MetricCard :header="$t('OVERVIEW_REPORTS.AGENT_STATUS.HEADER')">
        <div
          v-for="(metric, name, index) in agentStatusMetrics"
          :key="index"
          class="flex-1 min-w-0 pb-2"
        >
          <h3 class="text-base text-n-slate-11">
            {{ name }}
          </h3>
          <p class="text-n-slate-12 text-3xl mb-0 mt-1">
            {{ metric }}
          </p>
        </div>
      </MetricCard>
    </div>
    <div class="w-full basis-full">
      <MetricCard
        :header="t(`${accounti18nKey}.OPENED_BY_HEADER`)"
        :is-loading="uiFlags.isFetchingAccountConversationMetric"
        :loading-message="t(`${accounti18nKey}.LOADING_MESSAGE`)"
      >
        <div
          v-for="(metric, name, index) in openedByMetrics"
          :key="index"
          class="flex-1 min-w-0 pb-2"
        >
          <h3 class="text-base text-n-slate-11">
            {{ name }}
          </h3>
          <p class="text-n-slate-12 text-3xl mb-0 mt-1">
            {{ metric }}
          </p>
        </div>
      </MetricCard>
    </div>
  </div>
</template>
