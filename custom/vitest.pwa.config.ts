import path from 'path';
import { defineConfig } from 'vitest/config';
import baseConfig from '../vitest.config';

// FORK: keep setup files inside the PWA worktree when running targeted tests
export default defineConfig({
  ...baseConfig,
  test: {
    ...baseConfig.test,
    setupFiles: [
      path.resolve('node_modules/fake-indexeddb/auto/index.mjs'),
      path.resolve('vitest.setup.js'),
    ],
  },
});
