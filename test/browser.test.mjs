// Real browser execution, including fail-closed unsupported browser profiles.
// ref:DEC-host-sdk-direct-haskell
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, firefox, webkit} from '@playwright/test';
/** Limits the test server to SDK artifacts and examples. ref:REQ-host-sdk-runtime-boundary */
const root = fileURLToPath(new URL('../', import.meta.url));

for (const [name, engine] of Object.entries({
  chromium,
  firefox,
  webkit,
  'chromium-isolated': chromium,
}))
{
  test(
    `plain-page ${name}: typed component or explicit unsupported`,
    {timeout: 120000},
    async t =>
    {
      const server = createServer(async (req, res) =>
      {
        try
        {
          if (req.url === '/forged/manifest.json')
          {
            const manifest = JSON.parse(
              await readFile(
                path.join(root, 'assets/haskell-contract/manifest.json'),
                'utf8',
              ),
            );
            manifest.assets['guest.js'] = '0'.repeat(64);
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify(manifest));
            return;
          }
          const pathname = new URL(req.url, 'http://localhost').pathname;
          const file = path.resolve(root, '.' + pathname);
          if (file !== root.slice(0, -1) && !file.startsWith(root))
          {
            res.writeHead(403).end();
            return;
          }
          const data =
            pathname === '/'
              ? Buffer.from('<!doctype html><title>SDK acceptance</title>')
              : await readFile(file);
          res.setHeader(
            'Content-Type',
            file.endsWith('.wasm')
              ? 'application/wasm'
              : /\.(mjs|js)$/.test(file)
                ? 'text/javascript'
                : file.endsWith('.json')
                  ? 'application/json'
                  : 'text/html',
          );
          if (name.endsWith('isolated'))
          {
            res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
            res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
          }
          res.setHeader(
            'Content-Security-Policy',
            "default-src 'self'; script-src 'self' blob: 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'",
          );
          res.end(data);
        }
        catch
        {
          res.writeHead(404).end();
        }
      });
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      t.after(() =>
      {
        server.closeAllConnections();
        return new Promise(resolve => server.close(resolve));
      });
      // WebKit's ephemeral contexts reject OPFS; exercise its persistent profile explicitly.
      const profile =
        name === 'webkit'
          ? await mkdtemp(path.join(tmpdir(), 'host-sdk-webkit-'))
          : undefined;
      const browser = profile
        ? await engine.launchPersistentContext(profile, {headless: true})
        : await engine.launch({headless: true});
      t.after(async () =>
      {
        await browser.close();
        if (profile) await rm(profile, {recursive: true, force: true});
      });
      const page = await browser.newPage();
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      const result = await page.evaluate(async isolated =>
      {
        const {createHost: rawHost} = await import('/browser.mjs');
        const createHost = async options =>
        {
          if (options.manifest.includes('/forged/'))
            return rawHost({
              ...options,
              registration: {
                manifests: [],
                workerURL: new URL(
                  '/assets/contract/worker.mjs',
                  location.href,
                ),
              },
            });
          const module = await import(new URL('browser.mjs', options.manifest));
          return module.createApplication(options);
        };
        let host;
        try
        {
          host = await createHost({
            manifest:
              location.origin + '/assets/haskell-contract/manifest.json',
            limits: {timeout: 90000},
            grants: {
              async: {
                kind: 'native',
                validate: () => true,
                execute: async () =>
                {
                  await new Promise(r => setTimeout(r, 10));
                  return 'Haskell async';
                },
              },
            },
            deployment: isolated ? 'isolated' : 'standard',
          });
          const echo = await host.invoke('echo', ['héllo 😀']);
          let denied;
          try
          {
            await host.invoke('exercise', [
              'absent',
              {tag: 'get-value', val: 'secret'},
            ]);
          }
          catch (error)
          {
            denied = error.code;
          }
          const payload = {
            items: [{name: 'unicode', value: 'héllo 😀'}],
            enabled: true,
          };
          const roundTrip = await host.invoke('round-trip', [payload]);
          // The same typed resource and wide-integer contract runs in each guest.
          for (const fixture of ['contract', 'haskell-contract'])
          {
            const sample = await createHost({
              manifest: location.origin + `/assets/${fixture}/manifest.json`,
            });
            const other = await createHost({
              manifest: location.origin + `/assets/${fixture}/manifest.json`,
            });
            try
            {
              if (
                (await sample.invoke('scalar', [18446744073709551615n])) !==
                18446744073709551615n
              )
                throw Error('wide integer changed');
              const scalars = {
                integers: {
                  a: 255,
                  b: -128,
                  c: 65535,
                  d: -32768,
                  e: 4294967295,
                  f: -2147483648,
                  g: 18446744073709551615n,
                  h: -9223372036854775808n,
                },
                numbers: [{tag: 'large', val: 9007199254740993n}],
                bytes: [0, 128, 255],
                optional: null,
              };
              const roundtrip = await sample.invoke('scalars', [scalars]);
              if (
                roundtrip.integers.h !== scalars.integers.h ||
                roundtrip.numbers[0].val !== 9007199254740993n ||
                roundtrip.bytes.join(',') !== '0,128,255' ||
                roundtrip.optional !== null
              )
                throw Error('scalar payload changed');
              const resource = await sample.invoke('[constructor]snapshot', [
                ['one', '😀', 'three'],
              ]);
              if (
                (await sample.invoke('[method]snapshot.size', [resource])) !== 3
              )
                throw Error('resource size changed');
              if (
                (
                  await sample.invoke('[method]snapshot.read', [resource, 1, 1])
                )[0] !== '😀'
              )
                throw Error('resource bulk read changed');
              let denied = false;
              try
              {
                await other.invoke('[method]snapshot.size', [resource]);
              }
              catch (error)
              {
                denied = error.code === 'denied';
              }
              if (!denied) throw Error('cross-instance resource accepted');
              await sample.drop(resource);
              const consumed = await sample.invoke('[constructor]snapshot', [
                ['owned'],
              ]);
              if (
                (await sample.invoke('consume', [consumed])) !== 1 ||
                (await sample.invoke('destroyed')) !== 2
              )
                throw Error('resource ownership or destructor failed');
              if ((await sample.invoke('nothing')) !== undefined)
                throw Error('void result changed');
            }
            finally
            {
              sample.close();
              other.close();
            }
          }
          const directory = await navigator.storage.getDirectory();
          const file = await directory.getFileHandle('sample.txt', {
            create: true,
          });
          const writer = await file.createWritable();
          await writer.write('text example\n');
          await writer.close();
          const surface = document.createElement('div');
          document.body.append(surface);
          const sample = await createHost({
            manifest: location.origin + '/assets/contract/manifest.json',
            grants: {
              files: {
                kind: 'files',
                handle: directory,
                read: true,
                write: true,
              },
              readonly: {kind: 'files', handle: directory, read: true},
              ui: {kind: 'ui', surface},
              refused: {
                kind: 'native',
                validate: () => true,
                execute: () =>
                {
                  throw new DOMException(
                    'permission refused',
                    'NotAllowedError',
                  );
                },
              },
              env: {kind: 'environment', values: {PUBLIC: 'explicit'}},
              store: {
                kind: 'storage',
                namespace: 'app/plugin',
                quota: 16,
                read: true,
                write: true,
              },
              tool: {
                kind: 'native',
                validate: value => value === 'safe',
                execute: async () =>
                {
                  await new Promise(r => setTimeout(r, 10));
                  return 'async 😀';
                },
              },
            },
          });
          const perform = (name, tag, val) =>
            sample.invoke('exercise', [name, {tag, val}]);
          const checks = {
            haskellAsync: await host.invoke('exercise', [
              'async',
              {tag: 'invoke', val: 'wait'},
            ]),
          };
          try
          {
            checks.file = await perform('files', 'read-text', 'sample.txt');
            try
            {
              await perform('refused', 'invoke', '');
            }
            catch (error)
            {
              checks.consent = error.code;
            }
            await perform('files', 'write-text', {
              key: 'sample.txt',
              value: 'written 😀',
            });
            checks.written = await (await file.getFile()).text();
            for (const [key, provider, tag, val] of [
              [
                'readonly',
                'readonly',
                'write-text',
                {key: 'sample.txt', value: 'forbidden'},
              ],
              ['traversal', 'files', 'read-text', '../secret'],
            ])
            {
              try
              {
                await perform(provider, tag, val);
              }
              catch (error)
              {
                checks[key] = error.code;
              }
            }
            await perform(
              'ui',
              'render',
              '<script>parent.compromised=true</script><a href="/forbidden">link</a>',
            );
            const frame = surface.querySelector('iframe');
            checks.ui =
              frame.hasAttribute('sandbox') &&
              frame.getAttribute('sandbox') === '' &&
              frame.srcdoc.includes('&lt;script&gt;') &&
              !frame.srcdoc.includes('<a ');
            await perform('ui', 'render', 'replacement');
            checks.uiReplaced =
              surface.querySelectorAll('iframe').length === 1 &&
              !frame.isConnected;
            checks.async = await perform('tool', 'invoke', 'safe');
            checks.env = await perform('env', 'get-value', 'PUBLIC');
            const foreignHandle = await sample.invoke('echo', [
              '__export-handle',
            ]);
            const other = await createHost({
              manifest: location.origin + '/assets/contract/manifest.json',
            });
            try
            {
              await other.invoke('exercise', [
                `__import-handle:${foreignHandle}`,
                {tag: 'get-value', val: 'PUBLIC'},
              ]);
            }
            catch (error)
            {
              checks.crossInstance = error.code;
            }
            finally
            {
              other.close();
            }
            await perform('store', 'put-value', {key: 'k', value: 'v'});
            checks.storage = await perform('store', 'get-value', 'k');
            try
            {
              await perform('store', 'put-value', {
                key: 'k',
                value: 'x'.repeat(40),
              });
            }
            catch (e)
            {
              checks.quota = e.code;
            }
            checks.noWasi = await sample.invoke('echo', ['__wasi-file']);
            checks.noEnv = await sample.invoke('echo', ['__wasi-env']);
            for (let i = 0; i < 20; i++)
              if (
                (await sample.invoke('echo', ['é😀'.repeat(10000)])) !==
                'é😀'.repeat(10000)
              )
                throw Error('Unicode mismatch');
            try
            {
              await perform('__forge', 'get-value', 'secret');
            }
            catch (e)
            {
              checks.forged = e.code;
            }
          }
          finally
          {
            sample.close();
            checks.uiDisposed = surface.children.length === 0;
            surface.remove();
            await directory.removeEntry('sample.txt');
          }
          for (const mode of ['__allocate', '__loop'])
          {
            const attacker = await createHost({
              manifest: location.origin + '/assets/contract/manifest.json',
              limits: {timeout: 2000},
            });
            try
            {
              await attacker.invoke('echo', [mode]);
              checks[mode] = 'unexpected success';
            }
            catch (e)
            {
              checks[mode] = e.code;
            }
            finally
            {
              attacker.close();
            }
          }
          const waiting = await createHost({
            manifest: location.origin + '/assets/contract/manifest.json',
            grants: {
              wait: {
                kind: 'native',
                validate: () => true,
                execute: (_, {signal}) =>
                  new Promise((_, reject) =>
                    signal.addEventListener(
                      'abort',
                      () => reject(signal.reason),
                      {once: true},
                    ),
                  ),
              },
            },
          });
          const pending = waiting.invoke('exercise', [
            'wait',
            {tag: 'invoke', val: 'wait'},
          ]);
          setTimeout(() => waiting.revoke(), 20);
          try
          {
            await pending;
          }
          catch (e)
          {
            checks.cancel = e.code;
          }
          finally
          {
            waiting.close();
          }
          try
          {
            await createHost({
              manifest: location.origin + '/forged/manifest.json',
            });
          }
          catch (e)
          {
            checks.forgedManifest = e.code;
          }
          const manifest = await (await fetch('/forged/manifest.json')).json();
          checks.directWorker = await new Promise(resolve =>
          {
            const worker = new Worker('/assets/contract/worker.mjs', {
              type: 'module',
            });
            worker.onmessage = event =>
            {
              resolve(event.data.error?.code);
              worker.terminate();
            };
            worker.postMessage({
              init: true,
              manifest,
              limits: {requests: 10},
              providers: [],
            });
          });
          checks.survives = await host.invoke('echo', ['independent']);
          const saved = WebAssembly.Suspending;
          try
          {
            WebAssembly.Suspending = undefined;
            await createHost({
              manifest:
                location.origin + '/assets/haskell-contract/manifest.json',
            });
          }
          catch (e)
          {
            checks.unsupported = e.code;
          }
          finally
          {
            WebAssembly.Suspending = saved;
          }
          return {echo, denied, roundTrip, checks};
        }
        catch (error)
        {
          return {error: error.code, message: error.message};
        }
        finally
        {
          host?.close();
        }
      }, name.endsWith('isolated'));
      if (result.error === 'unsupported')
      {
        t.diagnostic(
          `${name}: unsupported (${result.message}); no fallback executed`,
        );
        assert.match(result.message, /JSPI|secure context/);
        return;
      }
      assert.equal(result.error, undefined, result.message);
      assert.equal(result.echo, 'héllo 😀');
      assert.equal(result.denied, 'denied');
      assert.deepEqual(result.roundTrip, {
        items: [{name: 'unicode', value: 'héllo 😀'}],
        enabled: true,
      });
      assert.deepEqual(result.checks, {
        haskellAsync: 'Haskell async',
        file: 'text example\n',
        consent: 'denied',
        written: 'written 😀',
        readonly: 'denied',
        traversal: 'denied',
        ui: true,
        uiReplaced: true,
        uiDisposed: true,
        async: 'async 😀',
        env: 'explicit',
        crossInstance: 'failed',
        storage: 'v',
        quota: 'exhausted',
        noWasi: 'denied',
        noEnv: 'denied',
        forged: 'failed',
        __allocate: 'exhausted',
        __loop: 'exhausted',
        cancel: 'cancelled',
        forgedManifest: 'denied',
        directWorker: 'denied',
        survives: 'independent',
        unsupported: 'unsupported',
      });
    },
  );
}
