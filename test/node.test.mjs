// Execute real components; no fake runtime substitutes for containment evidence.
// ref:DEC-host-sdk-direct-haskell
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  mkdir,
  writeFile,
  readFile,
  symlink,
  rm,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createServer} from 'node:http';
import {createHost, trustedJavaScript} from '../node.mjs';
import {nativeArtifacts} from '../assets/contract/node-registration.mjs';
import {nativeArtifacts as haskellNative} from '../assets/haskell-contract/node-registration.mjs';
/** Selects the real second-language component for capability negative controls. ref:REQ-host-sdk-runtime-boundary */
const manifest = new URL('../assets/contract/manifest.json', import.meta.url);
/** Constructs a new runtime store for every isolated contract test. ref:REQ-host-sdk-runtime-boundary */
const create = options =>
  createHost({
    manifest,
    nativeArtifacts,
    ...options,
  });
/** Checks the denial classification, not merely whether an operation throws. ref:REQ-host-sdk-runtime-boundary */
const denied = promise =>
  assert.rejects(promise, error => error.code === 'denied');
/** Invokes the same typed host contract used by the Haskell pilot. ref:REQ-host-sdk-runtime-boundary */
const exercise = (host, name, tag, val) =>
  host.invoke('exercise', [name, {tag, val}]);

test(
  'Rust guest shares capabilities, denies traversal and symlink escapes, and isolates instances',
  {timeout: 120000},
  async t =>
  {
    const root = await mkdtemp(path.join(tmpdir(), 'host-sdk-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    await mkdir(path.join(root, 'allowed'));
    await writeFile(path.join(root, 'secret'), 'outside');
    await writeFile(path.join(root, 'allowed', 'a.txt'), 'inside 😀');
    await symlink(
      path.join(root, 'secret'),
      path.join(root, 'allowed', 'escape'),
    );
    const options = {
      grants: {
        files: {
          kind: 'files',
          root: path.join(root, 'allowed'),
          read: true,
          write: false,
        },
        env: {kind: 'environment', values: {PUBLIC: 'explicit'}},
        store: {
          kind: 'storage',
          namespace: 'app/plugin-a',
          quota: 32,
          read: true,
          write: true,
        },
      },
    };
    const host = await create(options);
    t.after(() => host.close());
    options.grants.files.write = true;
    options.grants.env.values.SECRET = 'escalation';
    assert.equal(
      await exercise(host, 'files', 'read-text', 'a.txt'),
      'inside 😀',
    );
    for (const target of ['../secret', '/etc/passwd', 'escape'])
      await denied(exercise(host, 'files', 'read-text', target));
    await denied(
      exercise(host, 'files', 'write-text', {key: 'a.txt', value: 'changed'}),
    );
    await denied(exercise(host, 'missing', 'get-value', 'secret'));
    await denied(exercise(host, 'env', 'get-value', 'SECRET'));
    assert.equal(
      await exercise(host, 'env', 'get-value', 'PUBLIC'),
      'explicit',
    );
    await exercise(host, 'store', 'put-value', {key: 'k', value: 'v'});
    assert.equal(await exercise(host, 'store', 'get-value', 'k'), 'v');
    await assert.rejects(
      exercise(host, 'store', 'put-value', {key: 'k', value: 'x'.repeat(40)}),
      e => e.code === 'exhausted',
    );
    process.env.HOST_SDK_SECRET = 'must-not-inherit';
    assert.equal(await host.invoke('echo', ['__wasi-env']), 'denied');
    assert.equal(await host.invoke('echo', ['__wasi-file']), 'denied');
    const other = await create();
    t.after(() => other.close());
    await denied(exercise(other, 'files', 'read-text', 'a.txt'));
    const foreignHandle = await host.invoke('echo', ['__export-handle']);
    await assert.rejects(
      exercise(
        other,
        `__import-handle:${foreignHandle}`,
        'get-value',
        'PUBLIC',
      ),
      e => e.code === 'failed',
    );
    const forged = await create();
    t.after(() => forged.close());
    await assert.rejects(
      exercise(forged, '__forge', 'get-value', 'secret'),
      e => e.code === 'failed',
    );
    assert.equal(
      await exercise(host, 'files', 'read-text', 'a.txt'),
      'inside 😀',
    );
  },
);

test(
  'async providers, repeated Unicode and large responses, concurrent instances and revocation',
  {timeout: 120000},
  async t =>
  {
    let calls = 0,
      aborted = false;
    const host = await create({
      grants: {
        tool: {
          kind: 'native',
          validate: value => value === 'allowed',
          execute: async (_, {signal}) =>
          {
            calls++;
            await new Promise((resolve, reject) =>
            {
              const timer = setTimeout(resolve, 25);
              signal.addEventListener(
                'abort',
                () =>
                {
                  aborted = true;
                  clearTimeout(timer);
                  reject(signal.reason);
                },
                {once: true},
              );
            });
            return 'asynchronous 😀';
          },
        },
      },
    });
    t.after(() => host.close());
    await denied(exercise(host, 'tool', 'invoke', 'wrong'));
    assert.equal(calls, 0);
    assert.equal(
      await exercise(host, 'tool', 'invoke', 'allowed'),
      'asynchronous 😀',
    );
    const text = 'é😀'.repeat(100000);
    for (let i = 0; i < 30; i++)
      assert.equal(await host.invoke('echo', [text]), text);
    const other = await create();
    t.after(() => other.close());
    assert.deepEqual(
      await Promise.all([
        host.invoke('echo', ['one']),
        other.invoke('echo', ['two']),
      ]),
      ['one', 'two'],
    );
    const pending = exercise(host, 'tool', 'invoke', 'allowed');
    await new Promise(resolve => setTimeout(resolve, 10));
    host.revoke();
    await assert.rejects(pending, e => e.code === 'cancelled');
    assert.equal(aborted, true);
    await assert.rejects(
      host.invoke('echo', ['later']),
      e => e.code === 'cancelled',
    );
    assert.equal(await other.invoke('echo', ['still alive']), 'still alive');
  },
);

test(
  'network allowlist rejects unauthorized destinations and redirects',
  {timeout: 120000},
  async t =>
  {
    let forbidden = 0;
    const server = createServer((request, response) =>
    {
      if (request.url === '/allowed') response.end('allowed');
      else if (request.url === '/redirect')
      {
        response.writeHead(302, {location: '/forbidden'});
        response.end();
      }
      else
      {
        forbidden++;
        response.end('secret');
      }
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() =>
    {
      server.closeAllConnections();
      server.close();
    });
    const origin = `http://127.0.0.1:${server.address().port}`;
    const host = await create({
      grants: {
        net: {
          kind: 'network',
          allowHttp: true,
          destinations: [
            {origin, path: '/allowed', methods: ['GET']},
            {origin, path: '/redirect', methods: ['GET']},
          ],
        },
      },
    });
    t.after(() => host.close());
    const fetch = path =>
      exercise(host, 'net', 'fetch', {
        url: origin + path,
        method: 'get',
        body: '',
      });
    assert.equal(await fetch('/allowed'), 'allowed');
    await denied(fetch('/forbidden'));
    await denied(fetch('/redirect'));
    assert.equal(forbidden, 0);
  },
);

for (const [mode, limits, code] of [
  ['__loop', {fuel: 100000}, 'exhausted'],
  ['__allocate', {memory: 16 * 1024 * 1024}, 'exhausted'],
  ['__panic', {}, 'failed'],
])
{
  test(
    `malicious guest ${mode} terminates without host access`,
    {timeout: 60000},
    async () =>
    {
      const host = await create({limits});
      try
      {
        await assert.rejects(
          host.invoke('echo', [mode]),
          error => error.code === code,
        );
      }
      finally
      {
        host.close();
      }
    },
  );
}

test(
  'hostile profile rejects trusted escapes and enforces request/output limits',
  {timeout: 60000},
  async t =>
  {
    await denied(
      create({grants: {escape: trustedJavaScript(() => 'unrestricted')}}),
    );
    const host = await create({limits: {requests: 1, bytes: 128}});
    t.after(() => host.close());
    await assert.rejects(
      host.invoke('echo', ['x'.repeat(129)]),
      e => e.code === 'exhausted',
    );
    await denied(exercise(host, 'missing', 'get-value', 'value'));
    await assert.rejects(
      exercise(host, 'missing', 'get-value', 'value'),
      e => e.code === 'exhausted',
    );
    const output = await create({
      limits: {bytes: 128},
      grants: {
        tool: {
          kind: 'native',
          validate: () => true,
          execute: () => 'x'.repeat(129),
        },
      },
    });
    t.after(() => output.close());
    await assert.rejects(
      exercise(output, 'tool', 'invoke', 'allowed'),
      e => e.code === 'exhausted',
    );
  },
);

test(
  'direct Haskell bindings release repeated results and contain an escaping exception',
  {timeout: 60000},
  async t =>
  {
    const host = await createHost({
      nativeArtifacts: haskellNative,
      manifest: new URL(
        '../assets/haskell-contract/manifest.json',
        import.meta.url,
      ),
      limits: {memory: 32 * 1024 * 1024},
      grants: {env: {kind: 'environment', values: {KEY: 'value 😀'}}},
    });
    t.after(() => host.close());
    // Returned UTF-8 alone exceeds the 32 MiB memory budget across these calls.
    for (let i = 0; i < 400; i++)
    {
      assert.equal(
        await host.invoke('echo', ['é😀'.repeat(20000)]),
        'é😀'.repeat(20000),
      );
      assert.equal(await exercise(host, 'env', 'get-value', 'KEY'), 'value 😀');
    }
    const payload = {
      items: [
        {name: 'empty', value: ''},
        {name: 'unicode', value: '𐀀\0 café'},
      ],
      enabled: false,
    };
    assert.deepEqual(await host.invoke('round-trip', [payload]), payload);
    await assert.rejects(
      host.invoke('echo', ['__panic']),
      error => error.code === 'failed',
    );
  },
);
