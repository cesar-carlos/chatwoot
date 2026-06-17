const path = require('path');

const appDir = __dirname;
const rvmPath = '/usr/share/rvm/scripts/rvm';

module.exports = {
  apps: [
    {
      name: 'chatwoot-web',
      cwd: appDir,
      script: '/bin/bash',
      args: `-lc 'source ${rvmPath} && cd ${appDir} && bundle exec rails server -p 3000 -b 0.0.0.0 -e production'`,
      env: {
        RAILS_ENV: 'production',
        NODE_ENV: 'production',
        PORT: '3000',
      },
      max_memory_restart: '4G',
      kill_timeout: 30000,
    },
    {
      name: 'chatwoot-worker',
      cwd: appDir,
      script: '/bin/bash',
      args: `-lc 'source ${rvmPath} && cd ${appDir} && dotenv bundle exec sidekiq -C config/sidekiq.yml'`,
      env: {
        RAILS_ENV: 'production',
        NODE_ENV: 'production',
      },
      max_memory_restart: '1200M',
      kill_timeout: 30000,
    },
  ],
};
