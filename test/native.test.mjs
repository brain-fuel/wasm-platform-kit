// Native deserialization requires build authority independent of guest manifests.
// ref:DEC-host-sdk-precompiled-node
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  copyFile,
  writeFile,
  readFile,
  rm,
  truncate,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHost} from '../node.mjs';
import {nativeArtifacts} from '../assets/contract/node-registration.mjs';
const manifest = new URL('../assets/contract/manifest.json', import.meta.url);
const platform = `${process.platform}-${process.arch}`;

/** Copies trusted fixture bytes for destructive negative controls. ref:REQ-host-sdk-runtime-boundary */
async function fixture(t)
{
  const root = await mkdtemp(path.join(tmpdir(), 'host-sdk-native-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const localManifest = pathToFileURL(path.join(root, 'manifest.json'));
  const artifact = pathToFileURL(path.join(root, 'native.cwasm'));
  await copyFile(manifest, localManifest);
  await copyFile(nativeArtifacts[platform].artifact, artifact);
  return {
    root,
    artifact,
    manifest: localManifest,
    nativeArtifacts: {
      [platform]: {...nativeArtifacts[platform], artifact},
    },
  };
}

test('precompiled execution needs no portable source and uses an immutable verified snapshot', async t =>
{
  const options = await fixture(t);
  const host = await createHost(options);
  t.after(() => host.close());
  assert.equal(host.identity.compilation, 'precompiled');
  assert.equal(
    host.identity.nativeArtifact,
    nativeArtifacts[platform].nativeSha256,
  );
  assert.equal(
    host.identity.artifact,
    nativeArtifacts[platform].componentSha256,
  );
  // Original portable Wasm was never copied. Truncating the original native file
  // would invalidate an mmap of it; the verified private snapshot remains valid.
  await truncate(options.artifact, 0);
  assert.equal(
    await host.invoke('echo', ['snapshot survives']),
    'snapshot survives',
  );
});

test('guest manifests cannot register native code or trigger a source fallback', async t =>
{
  const options = await fixture(t);
  const guest = JSON.parse(await readFile(options.manifest, 'utf8'));
  guest.nativeArtifacts = options.nativeArtifacts;
  await writeFile(options.manifest, JSON.stringify(guest));
  await assert.rejects(createHost({manifest: options.manifest}), {
    code: 'unsupported',
  });
  await rm(options.artifact);
  await assert.rejects(createHost(options), {code: 'failed'});
});

test('corruption, wrong component, engine settings and target are rejected', async t =>
{
  const options = await fixture(t);
  const original = options.nativeArtifacts[platform];
  for (const patch of [
    {componentSha256: '0'.repeat(64)},
    {configuration: 'different-engine'},
    {target: 'wrong-target'},
    {nativeSha256: '0'.repeat(64)},
  ])
    await assert.rejects(
      createHost({
        ...options,
        nativeArtifacts: {[platform]: {...original, ...patch}},
      }),
      {code: 'failed'},
    );
  await writeFile(options.artifact, 'corrupt native code');
  await assert.rejects(createHost(options), {code: 'failed'});
});

test('runtime source compilation is rejected with installation repair instructions', async () =>
{
  await assert.rejects(
    createHost({manifest, compilation: 'source'}),
    /npm rebuild/,
  );
  await assert.rejects(createHost({manifest, compilation: 'automatic'}), {
    code: 'unsupported',
  });
});
