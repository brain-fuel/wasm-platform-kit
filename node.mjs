// One helper process per instance. Revocation destroys its store and resources.
// ref:DEC-host-sdk-direct-haskell
import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createHash, randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {
  HostError,
  fail,
  configure,
  createBroker,
  byteLength,
  createResourceScope,
  outcomeCode,
  stringifyTransport,
  parseTransport,
  trustedJavaScript,
} from './policy.mjs';
export {HostError, trustedJavaScript};
export {trustedDOM, trustedNativeFFI, trustedProcess} from './policy.mjs';
const require = createRequire(import.meta.url);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const live = new Set();
const cleanup = new FinalizationRegistry(stop => stop());
process.once('exit', () =>
{
  for (const stop of live) stop();
});

/** Starts an isolated Wasmtime instance from the matching prebuilt npm platform package. */
export async function createHost(options = {})
{
  if (
    !['darwin', 'linux'].includes(process.platform) ||
    !['arm64', 'x64'].includes(process.arch)
  )
    fail(
      'unsupported',
      'Node native execution supports macOS/Linux x64 and ARM64 only; use WSL on Windows',
    );
  if (
    process.platform === 'linux' &&
    !process.report.getReport().header.glibcVersionRuntime
  )
    fail(
      'unsupported',
      'Linux native execution requires a detectable glibc runtime; musl is unsupported',
    );
  const compilation = options.compilation ?? 'precompiled';
  if (compilation !== 'precompiled')
    fail(
      'unsupported',
      'Runtime compilation is unavailable; run WASM_PLATFORM_KIT_BUILD_FROM_SOURCE=1 npm rebuild to prepare native artifacts during installation',
    );
  const platform = `${process.platform}-${process.arch}`;
  const approved = options.nativeArtifacts?.[platform];
  // Snapshot embedding-owned registration before the first await. A guest
  // manifest, including its hashes, is never an authority for native loading.
  const native = approved && {
    artifact: String(approved.artifact),
    componentSha256: approved.componentSha256,
    nativeSha256: approved.nativeSha256,
    configuration: approved.configuration,
    target: approved.target,
  };
  if (!native)
    fail(
      'unsupported',
      `no embedding-approved native artifact for ${platform}; reinstall with scripts enabled or run npm rebuild`,
    );
  const resources = createResourceScope();
  const configuration = configure(options);
  const {limits, grants} = configuration;
  const controller = new AbortController();
  const broker = createBroker(configuration, {
    signal: controller.signal,
    storage: options.storage,
  });
  let binary;
  try
  {
    binary = require.resolve(
      `wasm-platform-kit-${platform}/bin/host-sdk-runtime`,
    );
  }
  catch
  {
    fail(
      'unsupported',
      `no prebuilt runtime for ${process.platform}-${process.arch}; build platform packages before installation`,
    );
  }
  if (!options.manifest)
    fail('failed', 'an embedding-approved component manifest is required');
  const manifestURL = new URL(options.manifest, import.meta.url);
  const manifest = JSON.parse(await readFile(manifestURL, 'utf8'));
  if (
    manifest.sdk !== '0.2.0' ||
    !manifest.contract?.interfaces[manifest.interface]
  )
    fail('unsupported', 'SDK 0.2.0 typed manifest required');
  const resultType = type =>
  {
    if (typeof type !== 'number') return undefined;
    const kind = manifest.contract.types[type].kind;
    return kind.type !== undefined ? resultType(kind.type) : kind.result;
  };
  const component = new URL(manifest.component, manifestURL);
  if (
    native.componentSha256 !== manifest.sha256 ||
    native.configuration !== 'host-sdk-0.2.0/wasmtime-50.0.1/fuel-v1' ||
    !/^[a-f0-9]{64}$/.test(native.nativeSha256)
  )
    fail('failed', 'native artifact registration mismatch');
  if (new URL(native.artifact).protocol !== 'file:')
    fail('denied', 'native artifacts must be local files');
  const providerIdentity = sha256(
    Buffer.concat(
      await Promise.all(
        [
          'policy.mjs',
          'node.mjs',
          'browser.mjs',
          'worker.mjs',
          'client.mjs',
        ].map(name => readFile(new URL(name, import.meta.url))),
      ),
    ),
  );
  const runtimeIdentity = `wasmtime-50.0.1:${sha256(await readFile(binary))}`;
  const child = spawn(binary, [], {
    env: {},
    cwd: '/',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  if (options.keepAlive === false)
  {
    child.unref();
    child.stdin.unref();
    child.stdout.unref();
    child.stderr.unref();
  }

  const nativeGrants = Object.fromEntries(
    [...grants].map(([name, grant]) => [
      name,
      {
        kind: grant.kind,
        ...(grant.kind === 'files'
          ? {root: grant.root, read: !!grant.read, write: !!grant.write}
          : {}),
      },
    ]),
  );
  let closed = false,
    pending,
    text = '',
    stderr = '',
    timer;
  let queue = Promise.resolve();
  const send = message =>
  {
    if (!closed) child.stdin.write(stringifyTransport(message) + '\n');
  };
  const cleanupToken = {};
  const stop = (error = new HostError('cancelled', 'instance revoked')) =>
  {
    if (closed) return;
    closed = true;
    live.delete(stop);
    cleanup.unregister(cleanupToken);
    clearTimeout(timer);
    controller.abort(error);
    broker.dispose();
    child.kill('SIGKILL');
    pending?.reject(error);
    pending = undefined;
  };
  live.add(stop);
  const wait = () =>
    new Promise((resolve, reject) =>
    {
      pending = {resolve, reject};
      timer = setTimeout(
        () => stop(new HostError('exhausted', 'execution deadline')),
        limits.timeout,
      );
    });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.on('error', error => stop(new HostError('failed', error.message)));
  child.on('exit', () =>
    stop(new HostError('failed', stderr || 'runtime exited')),
  );
  child.stdin.on('error', error =>
    stop(new HostError('failed', error.message)),
  );
  child.stderr.on('data', bytes =>
  {
    stderr += bytes.toString();
    if (stderr.length > 8192) stderr = stderr.slice(0, 8192);
  });
  child.stdout.on('data', bytes =>
  {
    text += bytes.toString();
    if (byteLength(text) > limits.bytes * 6 + 8192)
      return stop(new HostError('exhausted', 'transport output limit'));
    let newline;
    while ((newline = text.indexOf('\n')) >= 0)
    {
      const line = text.slice(0, newline);
      text = text.slice(newline + 1);
      let message;
      try
      {
        message = parseTransport(line);
      }
      catch
      {
        return stop(new HostError('failed', 'invalid runtime message'));
      }
      if (message.hostRequest)
      {
        const {provider, request} = message.hostRequest;
        broker.perform(provider, request).then(
          value => send({value}),
          error =>
            send({
              error: {
                code:
                  error.code ??
                  (controller.signal.aborted ? 'cancelled' : 'failed'),
                message: error.message,
              },
            }),
        );
        continue;
      }
      const active = pending;
      pending = undefined;
      clearTimeout(timer);
      if (!active)
        return stop(new HostError('failed', 'unexpected runtime response'));
      if (message.error)
      {
        active.reject(new HostError(message.error.code, message.error.message));
        stop();
      }
      else active.resolve(message);
    }
  });
  const ready = wait();
  send({
    component: fileURLToPath(component),
    compilation,
    ...(compilation === 'precompiled'
      ? {
          nativeArtifact: fileURLToPath(native.artifact),
          nativeRegistration: {
            componentSha256: native.componentSha256,
            nativeSha256: native.nativeSha256,
            configuration: native.configuration,
            target: native.target,
          },
        }
      : {}),
    sha256: manifest.sha256,
    limits,
    grants: nativeGrants,
  });
  const identity = await ready;
  const host = Object.freeze({
    identity: Object.freeze({
      ...identity,
      runtime: runtimeIdentity,
      provider: providerIdentity,
      instance: randomUUID(),
      policy: sha256(JSON.stringify([...grants]) + JSON.stringify(limits)),
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
          send({interface: manifest.interface, method, args: encoded});
          const response = await result;
          const value = response.value?.[0];
          const resultSchema = resultType(
            manifest.contract.interfaces[manifest.interface][method]?.result,
          );
          if (resultSchema && value?.tag === 'err')
            throw new HostError(
              outcomeCode(value.val?.code),
              typeof value.val === 'string'
                ? value.val
                : (value.val?.message ?? 'component returned an error'),
              resources.decode(value.val),
            );
          return resources.decode(
            resultSchema && value?.tag === 'ok' ? value.val : value,
          );
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
  cleanup.register(host, stop, cleanupToken);
  return host;
}
