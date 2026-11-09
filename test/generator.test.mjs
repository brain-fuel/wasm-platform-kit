// Rejected WIT and rejected Haskell must not masquerade as usable bindings.
// ref:DEC-host-sdk-direct-haskell
import {test} from 'node:test';
import {declarations} from '../tools/facade.mjs';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
/** Locates the actual generator and generated modules for negative compile checks. ref:REQ-host-sdk-runtime-boundary */
const root = fileURLToPath(new URL('../', import.meta.url));
test('unsupported WIT is rejected by generation', async t =>
{
  const dir = await mkdtemp(path.join(tmpdir(), 'wit-haskell-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  await writeFile(
    path.join(dir, 'world.wit'),
    'package test:unsupported; interface api { f: func(x: f64) -> result<string,string>; } world test { export api; }',
  );
  const result = spawnSync(
    process.execPath,
    [path.join(root, 'tools/generate.mjs'), dir, 'test', path.join(dir, 'out')],
    {encoding: 'utf8'},
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsupported.*integer lanes/);
});
test('generated Haskell rejects a string used as a resource', async t =>
{
  const dir = await mkdtemp(path.join(tmpdir(), 'wit-haskell-types-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const source = path.join(dir, 'Invalid.hs');
  await writeFile(
    source,
    '{-# LANGUAGE OverloadedStrings #-}\nmodule Invalid where\nimport Host\ninvalid = perform "forged" (HostRequestGetValue "secret")\n',
  );
  const result = spawnSync(
    path.join(
      process.env.HOME,
      '.ghc-wasm/wasm32-wasi-ghc/bin/wasm32-wasi-ghc',
    ),
    [
      '-fno-code',
      '-i' + path.join(root, 'generated'),
      '-i' + path.join(root, 'test/fixtures'),
      '-i' + path.join(root, 'haskell'),
      '-outputdir',
      dir,
      source,
    ],
    {encoding: 'utf8'},
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /HostProvider|IsString/);
});

// A method named then would turn an asynchronous client into a hanging thenable.
// ref:DEC-host-sdk-typed-application-boundary
test('façades reject Promise-assimilation names before emitting a client', () =>
{
  const operation = {
    name: 'then',
    kind: 'freestanding',
    params: [],
    result: null,
  };
  assert.throws(
    () =>
      declarations({types: [], interfaces: {api: {then: operation}}}, 'api'),
    /unsupported.*lifecycle/,
  );
  assert.throws(
    () =>
      declarations(
        {
          types: [{name: 'snapshot', kind: 'resource'}],
          interfaces: {
            api: {
              method: {
                ...operation,
                name: '[method]snapshot.then',
                kind: {method: 0},
                params: [{name: 'self', type: 0}],
              },
            },
          },
        },
        'api',
      ),
    /unsupported.*disposal/,
  );
});
