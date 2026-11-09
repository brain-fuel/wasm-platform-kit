// Real npm lifecycle checks: no compiler toolchain and no compilation at command time.
// ref:DEC-wpk-installation-preparation
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {
  mkdtemp,
  mkdir,
  copyFile,
  readFile,
  writeFile,
  readdir,
  rename,
  rm,
} from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {packageNativeArtifacts} from '../tools/native.mjs';
import {prepareNative} from '../install.mjs';
import {nativeArtifacts} from '../assets/contract/node-registration.mjs';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));
const platform = `${process.platform}-${process.arch}`;
const original = nativeArtifacts[platform];

/** Creates an isolated embedding with real compiler and native fixture artifacts. ref:DEC-wpk-installation-preparation */
async function fixture(t)
{
  const directory = await mkdtemp(path.join(tmpdir(), 'wpk-install-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  for (const file of ['manifest.json', 'component.wasm'])
    await copyFile(
      new URL(`../assets/contract/${file}`, import.meta.url),
      path.join(directory, file),
    );
  return {
    directory: pathToFileURL(directory + '/'),
    component: pathToFileURL(path.join(directory, 'component.wasm')),
    componentSha256: original.componentSha256,
  };
}

test(
  'npm installation prepares prebuilt or source artifacts; commands run with compiler removed',
  {timeout: 120000},
  async t =>
  {
    const options = await fixture(t);
    const directory = fileURLToPath(options.directory);
    const sdk = JSON.parse(
      await readFile(path.join(root, 'dist/packages.json'), 'utf8'),
    );
    const application = path.join(directory, 'application');
    await mkdir(application);
    for (const file of ['manifest.json', 'component.wasm'])
      await copyFile(path.join(directory, file), path.join(application, file));
    await packageNativeArtifacts({
      directory: application,
      artifacts: [{platform, file: original.artifact, registration: original}],
      packageDirectory: path.join(directory, 'native'),
      packagePrefix: 'wpk-install-fixture-native',
      version: '1.0.0',
    });
    await writeFile(
      path.join(application, 'package.json'),
      JSON.stringify({
        name: 'wpk-install-fixture',
        version: '1.0.0',
        type: 'module',
        scripts: {postinstall: 'node install.mjs'},
      }),
    );
    const pack = async cwd =>
      JSON.parse(
        (
          await exec(
            'npm',
            [
              'pack',
              '--ignore-scripts',
              '--json',
              '--pack-destination',
              directory,
            ],
            {cwd},
          )
        ).stdout,
      )[0].filename;
    const appArchive = path.join(directory, await pack(application));
    const nativeArchive = path.join(
      directory,
      await pack(path.join(directory, 'native', platform)),
    );
    for (const mode of [
      'prebuilt',
      'source',
      'missing-prebuilt',
      'ignore-scripts',
    ])
    {
      const consumer = path.join(directory, mode);
      await mkdir(consumer);
      await writeFile(
        path.join(consumer, 'package.json'),
        '{"private":true,"type":"module"}',
      );
      await exec(
        'npm',
        [
          'install',
          '--offline',
          '--no-audit',
          '--no-fund',
          ...(mode === 'ignore-scripts' ? ['--ignore-scripts'] : []),
          path.join(root, 'dist', sdk.runtime.file),
          path.join(root, 'dist', sdk.platforms[platform].file),
          ...(mode === 'prebuilt' || mode === 'source' ? [nativeArchive] : []),
          appArchive,
        ],
        {
          cwd: consumer,
          timeout: 60000,
          env: {
            ...process.env,
            WASM_PLATFORM_KIT_BUILD_FROM_SOURCE: mode === 'source' ? '1' : '0',
          },
        },
      );
      const helper = path.join(
        consumer,
        'node_modules',
        `wasm-platform-kit-${platform}`,
        'bin/host-sdk-source-runtime',
      );
      await rename(helper, helper + '.disabled');
      const app = path.join(consumer, 'node_modules/wpk-install-fixture');
      await writeFile(
        path.join(app, 'smoke.mjs'),
        `
      import assert from 'node:assert/strict';
      import {createHost} from 'wasm-platform-kit';
      import {nativeArtifacts} from './node-registration.mjs';
      const options = {manifest: new URL('./manifest.json', import.meta.url), nativeArtifacts};
      if (${JSON.stringify(mode)} === 'ignore-scripts') {
        await assert.rejects(createHost(options), /npm rebuild/);
      } else {
        const host = await createHost(options);
        try { assert.equal(host.identity.compilation, 'precompiled'); assert.equal(await host.invoke('echo', ['installed']), 'installed'); }
        finally { host.close(); }
      }
      await assert.rejects(createHost({...options, compilation: 'source'}), /npm rebuild/);
    `,
      );
      await exec(process.execPath, [path.join(app, 'smoke.mjs')], {
        cwd: consumer,
        timeout: 10000,
      });
      if (mode === 'source' || mode === 'missing-prebuilt')
      {
        const packed = JSON.parse(
          (
            await exec(
              'npm',
              ['pack', '--dry-run', '--ignore-scripts', '--json'],
              {cwd: app},
            )
          ).stdout,
        )[0];
        assert.ok(
          !packed.files.some(file => file.path.startsWith('.native/')),
          'installed state must not enter published archives',
        );
      }
    }
  },
);

test('failed or cancelled installation cannot publish a partial native registration', async t =>
{
  const options = await fixture(t);
  const registration = new URL(
    `.native/${platform}/registration.json`,
    options.directory,
  );
  await assert.rejects(
    prepareNative({
      ...options,
      componentSha256: '0'.repeat(64),
      fromSource: true,
    }),
    /integrity mismatch/,
  );
  await assert.rejects(readFile(registration), {code: 'ENOENT'});
  await assert.rejects(
    prepareNative({...options, fromSource: true, signal: AbortSignal.abort()}),
    {name: 'AbortError'},
  );
  await assert.rejects(
    prepareNative({...options, fromSource: true, timeout: 1}),
  );
  assert.deepEqual(
    await readdir(new URL(`.native/${platform}/`, options.directory)),
    [],
  );
  await prepareNative({...options, fromSource: true});
  const good = await readFile(registration, 'utf8');
  await writeFile(options.component, 'corrupt');
  await assert.rejects(
    prepareNative({...options, fromSource: true}),
    /integrity mismatch/,
  );
  assert.equal(await readFile(registration, 'utf8'), good);
  await assert.rejects(
    prepareNative({
      ...options,
      prebuiltArtifacts: {
        [platform]: {...original, nativeSha256: '0'.repeat(64)},
      },
    }),
    /integrity mismatch/,
  );
});
