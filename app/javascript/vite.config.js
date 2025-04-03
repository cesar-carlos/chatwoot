import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    host: `https://${process.env.VITE_HOST || 'localhost'}`,
    port: 3036,
  },
});
