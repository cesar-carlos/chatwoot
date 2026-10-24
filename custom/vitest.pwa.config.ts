import fs from 'fs';
import path from 'path';
import { defineConfig } from 'vitest/config';
import baseConfig from '../vitest.config';

// FORK: a worktree may symlink node_modules to the primary checkout. Vite
// realpaths that link and refuses the setup file unless the real directory
// is allowed.
const nodeModules = fs.realpathSync(path.resolve('node_modules'));

export default defineConfig({
  ...baseConfig,
  server: {
    fs: {
      allow: [path.resolve('.'), nodeModules],
    },
  },
  test: {
    ...baseConfig.test,
    setupFiles: ['fake-indexeddb/auto', path.resolve('vitest.setup.js')],
  },
});
