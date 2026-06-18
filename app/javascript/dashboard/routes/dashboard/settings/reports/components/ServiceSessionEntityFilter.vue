<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { buildFilterList } from './SLA/helpers/SLAFilterHelpers';
import {
  parseServiceSessionEntityURLParams,
  generateServiceSessionEntityURLParams,
} from '../helpers/reportFilterHelper';
import FilterButton from 'dashboard/components/ui/Dropdown/DropdownButton.vue';
import ActiveFilterChip from './Filters/v3/ActiveFilterChip.vue';
import AddFilterChip from './Filters/v3/AddFilterChip.vue';

const emit = defineEmits(['filterChange']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const showDropdownMenu = ref(false);
const showSubDropdownMenu = ref(false);
const activeFilterType = ref('');
const appliedFilters = ref({
  inbox_id: null,
  team_id: null,
  user_ids: null,
  label_ids: null,
});

const filterTypeMap = {
  inboxes: 'inbox_id',
  teams: 'team_id',
  agents: 'user_ids',
  labels: 'label_ids',
};

const filterPlaceholderForType = type => {
  if (type === 'inboxes') {
    return t('SLA_REPORTS.DROPDOWN.INPUT_PLACEHOLDER.INBOXES');
  }
  if (type === 'teams') {
    return t('SLA_REPORTS.DROPDOWN.INPUT_PLACEHOLDER.TEAMS');
  }
  if (type === 'agents') {
    return t('SLA_REPORTS.DROPDOWN.INPUT_PLACEHOLDER.AGENTS');
  }
  return t('SLA_REPORTS.DROPDOWN.INPUT_PLACEHOLDER.LABELS');
};

const agents = computed(() => store.getters['agents/getAgents']);
const inboxes = computed(() => store.getters['inboxes/getInboxes']);
const teams = computed(() => store.getters['teams/getTeams']);
const labels = computed(() => store.getters['labels/getLabels']);

const filterListMenuItems = computed(() => {
  const filterTypes = [
    { id: '1', name: t('SLA_REPORTS.DROPDOWN.INBOXES'), type: 'inboxes' },
    { id: '2', name: t('SLA_REPORTS.DROPDOWN.TEAMS'), type: 'teams' },
    { id: '3', name: t('SLA_REPORTS.DROPDOWN.AGENTS'), type: 'agents' },
    { id: '4', name: t('SLA_REPORTS.DROPDOWN.LABELS'), type: 'labels' },
  ];

  const activeFilterTypes = Object.entries(appliedFilters.value)
    .filter(([, value]) => value)
    .map(([key]) => {
      const entry = Object.entries(filterTypeMap).find(
        ([, paramKey]) => paramKey === key
      );
      return entry?.[0];
    })
    .filter(Boolean);

  const sources = {
    agents: agents.value,
    inboxes: inboxes.value,
    teams: teams.value,
    labels: labels.value,
  };

  return filterTypes
    .filter(({ type }) => !activeFilterTypes.includes(type))
    .map(({ id, name, type }) => ({
      id,
      name,
      type,
      options: buildFilterList(sources[type], type),
    }));
});

const activeFilters = computed(() => {
  const sources = {
    agents: agents.value,
    inboxes: inboxes.value,
    teams: teams.value,
    labels: labels.value,
  };

  return Object.entries(appliedFilters.value)
    .filter(([, value]) => value)
    .map(([key, value]) => {
      const type = Object.entries(filterTypeMap).find(
        ([, paramKey]) => paramKey === key
      )?.[0];
      const source = sources[type] || [];
      const item = source.find(
        filterItem => filterItem.id.toString() === value.toString()
      );

      return {
        id: item?.id,
        name: type === 'labels' ? item?.title : item?.name,
        type,
        key,
      };
    })
    .filter(filter => filter.id);
});

const hasActiveFilters = computed(() =>
  Object.values(appliedFilters.value).some(value => value !== null)
);

const isAllFilterSelected = computed(() => !filterListMenuItems.value.length);

const updateURLParams = () => {
  const entityParams = generateServiceSessionEntityURLParams(
    appliedFilters.value
  );
  const clearedKeys = ['inbox_id', 'team_id', 'user_ids', 'label_ids'];
  const nextQuery = { ...route.query };

  clearedKeys.forEach(key => {
    delete nextQuery[key];
  });

  router.replace({ query: { ...nextQuery, ...entityParams } });
};

const emitChange = () => {
  updateURLParams();
  emit('filterChange', { ...appliedFilters.value });
};

const showDropdown = () => {
  showSubDropdownMenu.value = false;
  showDropdownMenu.value = !showDropdownMenu.value;
};

const closeDropdown = () => {
  showDropdownMenu.value = false;
};

const openActiveFilterDropdown = filterType => {
  closeDropdown();
  activeFilterType.value = filterType;
  showSubDropdownMenu.value = !showSubDropdownMenu.value;
};

const closeActiveFilterDropdown = () => {
  activeFilterType.value = '';
  showSubDropdownMenu.value = false;
};

const resetDropdown = () => {
  closeDropdown();
  closeActiveFilterDropdown();
};

const addFilter = item => {
  const filterKey = filterTypeMap[item.type];
  appliedFilters.value[filterKey] = item.id;
  emitChange();
  resetDropdown();
};

const removeFilter = type => {
  const filterKey = filterTypeMap[type];
  appliedFilters.value[filterKey] = null;
  emitChange();
};

const clearAllFilters = () => {
  appliedFilters.value = {
    inbox_id: null,
    team_id: null,
    user_ids: null,
    label_ids: null,
  };
  emitChange();
  resetDropdown();
};

const initializeFromURL = () => {
  const urlFilters = parseServiceSessionEntityURLParams(route.query);
  appliedFilters.value = {
    inbox_id: urlFilters.inbox_id,
    team_id: urlFilters.team_id,
    user_ids: urlFilters.user_ids,
    label_ids: urlFilters.label_ids,
  };
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('inboxes/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  initializeFromURL();
  if (hasActiveFilters.value) {
    emitChange();
  }
});
</script>

<template>
  <div
    class="flex flex-col flex-wrap items-start gap-2 md:items-center md:flex-nowrap md:flex-row"
  >
    <div v-if="hasActiveFilters" class="flex flex-wrap gap-2 md:flex-nowrap">
      <ActiveFilterChip
        v-for="filter in activeFilters"
        v-bind="filter"
        :key="filter.type"
        :placeholder="filterPlaceholderForType(filter.type)"
        :active-filter-type="activeFilterType"
        :show-menu="showSubDropdownMenu"
        enable-search
        @toggle-dropdown="openActiveFilterDropdown"
        @close-dropdown="closeActiveFilterDropdown"
        @add-filter="addFilter"
        @remove-filter="removeFilter"
      />
    </div>
    <div
      v-if="hasActiveFilters && !isAllFilterSelected"
      class="w-full h-px border md:w-px md:h-5 border-n-weak"
    />
    <div class="flex items-center gap-2">
      <AddFilterChip
        v-if="!isAllFilterSelected"
        placeholder-i18n-key="SLA_REPORTS.DROPDOWN.INPUT_PLACEHOLDER"
        :name="$t('SLA_REPORTS.DROPDOWN.ADD_FIlTER')"
        :menu-option="filterListMenuItems"
        :show-menu="showDropdownMenu"
        :empty-state-message="$t('SLA_REPORTS.DROPDOWN.NO_FILTER')"
        @toggle-dropdown="showDropdown"
        @close-dropdown="closeDropdown"
        @add-filter="addFilter"
      />
      <div v-if="hasActiveFilters" class="w-px h-5 border border-n-weak" />
      <FilterButton
        v-if="hasActiveFilters"
        :button-text="$t('SLA_REPORTS.DROPDOWN.CLEAR_ALL')"
        @click="clearAllFilters"
      />
    </div>
  </div>
</template>
