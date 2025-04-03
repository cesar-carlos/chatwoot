module.exports = {
  apps: [
    {
      name: 'chatwoot',
      script: './start.sh',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      env: {
        NODE_ENV: 'production',
        RAILS_ENV: 'production',
        FRONTEND_URL: 'https://chat.se7esistemassinop.com.br',
        VITE_HOST: 'chat.se7esistemassinop.com.br',
      },
    },
  ],
};
