const path = require('path');
const fs = require('fs');

const appDir = __dirname;
// FORK: every host release must use persistent uploads before starting PM2.
const sharedStorageDir =
  process.env.CHATWOOT_SHARED_STORAGE_PATH || '/root/chatwoot/storage';
if (
  fs.realpathSync(path.join(appDir, 'storage')) !==
  fs.realpathSync(sharedStorageDir)
) {
  throw new Error(
    `Release storage must point to ${sharedStorageDir} before deploying`
  );
}
const rvmPath = '/usr/share/rvm/scripts/rvm';
// FORK: production is PM2 on the host, not Docker. Pin the Node bin so a
// non-interactive `bash -lc` does not keep an older nvm version from the dump.
const nodeBin = '/root/.nvm/versions/node/v24.21.0/bin';
const appPath = [nodeBin, process.env.PATH].filter(Boolean).join(':');

module.exports = {
  apps: [
    {
      name: 'chatwoot-web',
      cwd: appDir,
      script: '/bin/bash',
      // FORK: drop a local HTTP proxy inherited from the process manager. It
      // breaks outbound Evolution Go calls while inbound webhooks still arrive.
      args: `-lc 'unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GIT_HTTP_PROXY GIT_HTTPS_PROXY SOCKS_PROXY SOCKS5_PROXY socks_proxy socks5_proxy; source ${rvmPath} && cd ${appDir} && bundle exec rails server -p 3000 -b 0.0.0.0 -e production'`,
      env: {
        RAILS_ENV: 'production',
        NODE_ENV: 'production',
        PORT: '3000',
        PATH: appPath,
      },
      max_memory_restart: '4G',
      kill_timeout: 30000,
    },
    {
      name: 'chatwoot-worker',
      cwd: appDir,
      script: '/bin/bash',
      args: `-lc 'unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GIT_HTTP_PROXY GIT_HTTPS_PROXY SOCKS_PROXY SOCKS5_PROXY socks_proxy socks5_proxy; source ${rvmPath} && cd ${appDir} && dotenv bundle exec sidekiq -C config/sidekiq.yml'`,
      env: {
        RAILS_ENV: 'production',
        NODE_ENV: 'production',
        SIDEKIQ_CONCURRENCY: '8',
        PATH: appPath,
      },
      max_memory_restart: '2G',
      kill_timeout: 30000,
    },
  ],
};
