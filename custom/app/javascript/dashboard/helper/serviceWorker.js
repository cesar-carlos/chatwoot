import { PUSH_OPERATION_TIMEOUT_MS } from './pushSession';

export const waitForActiveWorker = registration => {
  if (registration.active?.state === 'activated')
    return Promise.resolve(registration);
  return new Promise((resolve, reject) => {
    const workers = new Set();
    let timeout;
    let check;
    const finish = error => {
      clearTimeout(timeout);
      registration.removeEventListener?.('updatefound', check);
      workers.forEach(worker =>
        worker.removeEventListener('statechange', check)
      );
      if (error) reject(error);
      else resolve(registration);
    };
    check = () => {
      if (registration.active?.state === 'activated') {
        finish();
        return;
      }
      [registration.installing, registration.waiting, registration.active]
        .filter(Boolean)
        .forEach(worker => {
          if (!workers.has(worker)) {
            workers.add(worker);
            worker.addEventListener('statechange', check);
          }
        });
    };
    timeout = setTimeout(
      () =>
        finish(
          Object.assign(new Error('Service worker activation timed out'), {
            code: 'PUSH_WORKER_TIMEOUT',
          })
        ),
      PUSH_OPERATION_TIMEOUT_MS
    );
    registration.addEventListener?.('updatefound', check);
    check();
  });
};
