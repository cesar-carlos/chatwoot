// FORK: hold the Vuex instance without importing store/index (avoids conversations → voice cycle)
let dashboardStore = null;

export const setRuntimeStore = store => {
  dashboardStore = store;
};

export const getRuntimeStore = () => dashboardStore;
