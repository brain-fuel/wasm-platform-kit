// Optional native packages preserve separate build authority and source-mode availability.
// ref:DEC-host-sdk-precompiled-node
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  readFile,
  copyFile,
  writeFile,
  mkdir,
  symlink,
  rm,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {packageNativeArtifacts} from '../tools/native.mjs';
import {createHost} from '../node.mjs';
import {prepareNative} from '../install.mjs';
import {nativeArtifacts as originals} from '../assets/contract/node-registration.mjs';

/** Packages real trusted compiler output into an isolated consumer directory. ref:REQ-host-sdk-runtime-boundary */
async function fixture(t)
{
  const directory = await mkdtemp(
    path.join(tmpdir(), 'host-sdk-native-package-'),
  );
  t.after(() => rm(directory, {recursive: true, force: true}));
  const platform = `${process.platform}-${process.arch}`;
  const native = originals[platform];
  await copyFile(
    new URL('../assets/contract/manifest.json', import.meta.url),
    path.join(directory, 'manifest.json'),
  );
  await copyFile(
    new URL('../assets/contract/component.wasm', import.meta.url),
    path.join(directory, 'component.wasm'),
  );
  await mkdir(path.join(directory, 'node_modules'), {recursive: true});
  await symlink(
    new URL('../', import.meta.url),
    path.join(directory, 'node_modules/wasm-platform-kit'),
  );
  return {
    directory,
    platform,
    artifacts: [{platform, file: native.artifact, registration: native}],
    packageDirectory: path.join(directory, 'packages'),
    packagePrefix: '@fixture/native',
    version: '1.0.0',
  };
}

test('missing platform artifacts are prepared during installation and execution only loads them', async t =>
{
  const options = await fixture(t);
  const dependencies = await packageNativeArtifacts(options);
  assert.equal(dependencies[`@fixture/native-${options.platform}`], '1.0.0');
  const {nativeArtifacts, prebuiltArtifacts} = await import(
    pathToFileURL(path.join(options.directory, 'node-registration.mjs'))
  );
  const manifest = pathToFileURL(path.join(options.directory, 'manifest.json'));
  await assert.rejects(createHost({manifest, nativeArtifacts}), {
    code: 'unsupported',
  });
  await prepareNative({
    directory: pathToFileURL(options.directory + '/'),
    component: new URL('./component.wasm', manifest),
    componentSha256: originals[options.platform].componentSha256,
    prebuiltArtifacts,
  });
  const source = await createHost({manifest, nativeArtifacts});
  assert.equal(source.identity.compilation, 'precompiled');
  t.after(() => source.close());
  assert.equal(await source.invoke('echo', ['source works']), 'source works');
  await mkdir(path.join(options.directory, 'node_modules/@fixture'), {
    recursive: true,
  });
  await symlink(
    path.join(options.packageDirectory, options.platform),
    path.join(
      options.directory,
      'node_modules/@fixture',
      `native-${options.platform}`,
    ),
  );
  const compiled = await createHost({manifest, nativeArtifacts});
  t.after(() => compiled.close());
  assert.equal(await compiled.invoke('echo', ['native works']), 'native works');
  const metadata = JSON.parse(
    await readFile(
      path.join(options.packageDirectory, options.platform, 'package.json'),
      'utf8',
    ),
  );
  assert.deepEqual(metadata.os, [process.platform]);
  assert.deepEqual(metadata.cpu, [process.arch]);
});

test('native packager rejects altered receipts before publishing registration', async t =>
{
  const options = await fixture(t);
  const output = path.join(options.directory, 'node-registration.mjs');
  await writeFile(output, 'existing authority');
  for (const patch of [
    {nativeSha256: '0'.repeat(64)},
    {componentSha256: '0'.repeat(64)},
    {target: 'wrong-target'},
    {configuration: 'different-engine'},
  ])
  {
    await assert.rejects(
      packageNativeArtifacts({
        ...options,
        artifacts: options.artifacts.map(entry => ({
          ...entry,
          registration: {...entry.registration, ...patch},
        })),
      }),
      /registration mismatch/,
    );
    assert.equal(await readFile(output, 'utf8'), 'existing authority');
  }
});
