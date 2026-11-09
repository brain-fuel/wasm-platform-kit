// Privileged handles and provider functions stay in the embedding page.
// ref:DEC-host-sdk-direct-haskell
import {
  HostError,
  fail,
  configure,
  createBroker,
  byteLength,
  createResourceScope,
  trustedJavaScript,
} from './policy.mjs';
export {HostError, trustedJavaScript};
export {trustedDOM, trustedNativeFFI, trustedProcess} from './policy.mjs';

const hex = bytes =>
  [...new Uint8Array(bytes)].map(x => x.toString(16).padStart(2, '0')).join('');
/** Starts a registered component in a worker with grants retained by the page broker. */
export async function createHost(options = {})
{
  const registration = options.registration;
  if (
    !registration ||
    !Array.isArray(registration.manifests) ||
    !registration.workerURL
  )
    fail('unsupported', 'host-generated browser registration required');
  const trustedManifests = new Set(registration.manifests);
  const resources = createResourceScope();
  const configuration = configure(options),
    {limits, grants} = configuration;
  if (
    !globalThis.isSecureContext ||
    !globalThis.crypto?.subtle ||
    typeof Worker === 'undefined'
  )
    fail('unsupported', 'secure context, workers and WebCrypto required');
  if (
    typeof WebAssembly.Suspending !== 'function' ||
    typeof WebAssembly.promising !== 'function'
  )
    fail('unsupported', 'WebAssembly JSPI required; no fallback runtime');
  if (!options.manifest)
    fail('failed', 'an embedding-approved component manifest is required');
  const manifestURL = new URL(options.manifest, import.meta.url);
  const response = await fetch(manifestURL, {
    credentials: 'omit',
    redirect: 'error',
  });
  if (!response.ok) fail('failed', 'manifest unavailable');
  const manifest = await response.json();
  const manifestDigest = hex(
    await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(JSON.stringify(manifest)),
    ),
  );
  if (!trustedManifests.has(manifestDigest))
    fail('denied', 'component is not in the host-generated artifact registry');
  if (options.deployment === 'isolated' && !globalThis.crossOriginIsolated)
    fail('unsupported', 'isolated deployment requires COOP/COEP headers');
  if (
    options.deployment &&
    !['standard', 'isolated'].includes(options.deployment)
  )
    fail('unsupported', 'unknown deployment profile');
  if (manifest.version !== 1 || manifest.browser?.memory > limits.memory)
    fail('unsupported', 'artifact exceeds browser memory policy');
  const controller = new AbortController();
  const broker = createBroker(configuration, {
    signal: controller.signal,
    storage: options.storage,
  });
  const worker = new Worker(registration.workerURL, {
    type: 'module',
  });
  let closed = false,
    pending,
    timer,
    queue = Promise.resolve();
  const stop = (error = new HostError('cancelled', 'instance revoked')) =>
  {
    if (closed) return;
    closed = true;
    clearTimeout(timer);
    controller.abort(error);
    worker.terminate();
    broker.dispose();
    pending?.reject(error);
    pending = undefined;
  };
  const wait = () =>
    new Promise((resolve, reject) =>
    {
      pending = {resolve, reject};
      timer = setTimeout(
        () => stop(new HostError('exhausted', 'execution deadline')),
        limits.timeout,
      );
    });
  worker.onerror = event => stop(new HostError('failed', event.message));
  worker.onmessage = event =>
  {
    const message = event.data;
    if (message.hostRequest)
    {
      const {provider, request} = message.hostRequest;
      broker.perform(provider, request).then(
        value =>
        {
          if (!closed)
            worker.postMessage({hostResponse: true, id: message.id, value});
        },
        error =>
        {
          if (!closed)
            worker.postMessage({
              hostResponse: true,
              id: message.id,
              error: {code: error.code ?? 'failed', message: error.message},
            });
        },
      );
      return;
    }
    const active = pending;
    pending = undefined;
    clearTimeout(timer);
    if (!active)
      return stop(new HostError('failed', 'unexpected worker response'));
    if (message.error)
    {
      active.reject(
        new HostError(
          message.error.code,
          message.error.message,
          resources.decode(message.error.payload),
        ),
      );
      // Guest-returned capability errors leave the component usable; traps do not.
      if (message.fatal) stop();
    }
    else active.resolve(message);
  };
  const ready = wait();
  worker.postMessage({
    init: true,
    manifestURL: manifestURL.href,
    manifest,
    limits,
    providers: [...grants.keys()],
  });
  try
  {
    await ready;
  }
  catch (error)
  {
    stop(error);
    throw error;
  }
  const policy = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(
      JSON.stringify([...grants]) + JSON.stringify(limits),
    ),
  );
  return Object.freeze({
    identity: Object.freeze({
      runtime: `jco-${manifest.generators.jco}`,
      artifact: manifest.sha256,
      provider: manifest.providers,
      instance: crypto.randomUUID(),
      policy: hex(policy),
      interface: manifest.interface,
    }),
    invoke(method, args = [], {signal} = {})
    {
      const run = async () =>
      {
        if (closed || signal?.aborted) fail('cancelled', 'instance revoked');
        const encoded = resources.encode(args);
        if (byteLength(encoded) > limits.bytes)
          fail('exhausted', 'input byte limit');
        const abort = () => stop();
        signal?.addEventListener('abort', abort, {once: true});
        try
        {
          const result = wait();
          worker.postMessage({method, args: encoded});
          return resources.decode((await result).value);
        }
        finally
        {
          signal?.removeEventListener('abort', abort);
        }
      };
      const result = queue.then(run);
      queue = result.catch(() =>
      {});
      return result;
    },
    drop(resource, controls)
    {
      return this.invoke('[resource-drop]', [resource], controls);
    },
    revoke: () => stop(),
    close: () => stop(),
  });
}
