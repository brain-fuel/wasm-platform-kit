// Real clean npm installation, with no build toolchain on PATH.
// ref:DEC-host-sdk-direct-haskell
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {
  readFile,
  mkdtemp,
  mkdir,
  writeFile,
  symlink,
  rm,
  copyFile,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
/** Captures installation and execution outcomes from real child processes. ref:REQ-host-sdk-runtime-boundary */
const exec = promisify(execFile);
/** Locates the staged SDK and matching platform package to pack. ref:REQ-host-sdk-runtime-boundary */
const root = fileURLToPath(new URL('../', import.meta.url));

test(
  'npm packs and installs the SDK and prebuilt helper without a compiler',
  {timeout: 120000},
  async t =>
  {
    const temp = await mkdtemp(path.join(tmpdir(), 'host-sdk-install-'));
    t.after(() => rm(temp, {recursive: true, force: true}));
    const platform = path.join(
      root,
      'platforms',
      `${process.platform}-${process.arch}`,
    );
    const pack = async cwd =>
      JSON.parse(
        (
          await exec(
            'npm',
            ['pack', '--ignore-scripts', '--json', '--pack-destination', temp],
            {cwd, maxBuffer: 4 * 1024 * 1024},
          )
        ).stdout,
      )[0].filename;
    const sdk = await pack(root),
      runtime = await pack(platform);
    await mkdir(path.join(temp, 'bin'));
    await symlink(process.execPath, path.join(temp, 'bin/node'));
    await writeFile(
      path.join(temp, 'package.json'),
      '{"type":"module","private":true}',
    );
    const npmPath = (await exec('which', ['npm'])).stdout.trim();
    await exec(
      npmPath,
      [
        'install',
        '--offline',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        path.join(temp, runtime),
        path.join(temp, sdk),
      ],
      {
        cwd: temp,
        env: {PATH: path.join(temp, 'bin'), HOME: process.env.HOME},
        maxBuffer: 4 * 1024 * 1024,
      },
    );
    await mkdir(path.join(temp, 'fixture'));
    for (const file of [
      'component.wasm',
      'manifest.json',
      'node-registration.mjs',
      `component.${process.platform}-${process.arch}.cwasm`,
    ])
      await copyFile(
        path.join(root, 'assets/contract', file),
        path.join(temp, 'fixture', file),
      );
    await writeFile(
      path.join(temp, 'smoke.mjs'),
      `import {createHost} from 'wasm-platform-kit';
import {nativeArtifacts} from './fixture/node-registration.mjs';
const host=await createHost({nativeArtifacts,manifest:new URL('./fixture/manifest.json',import.meta.url)});
try { if(await host.invoke('echo',['installed SDK passed'])!=='installed SDK passed')throw Error('bad result'); console.log('installed SDK passed'); } finally {host.close();}`,
    );
    const result = await exec(process.execPath, ['smoke.mjs'], {
      cwd: temp,
      env: {PATH: path.join(temp, 'bin')},
      maxBuffer: 1024 * 1024,
    });
    assert.match(result.stdout, /installed SDK passed/);
  },
);

// Building an unrelated guest from packed tools detects accidental checkout dependencies.
// ref:DEC-host-sdk-independent-repository
test(
  'packed build tools author an independent Haskell component',
  {timeout: 180000},
  async t =>
  {
    const temp = await mkdtemp(path.join(tmpdir(), 'host-sdk-author-'));
    t.after(() => rm(temp, {recursive: true, force: true}));
    const tarballs = [];
    for (const cwd of [
      root,
      path.join(root, 'packages/build'),
      path.join(root, 'platforms', `${process.platform}-${process.arch}`),
    ])
    {
      const packed = JSON.parse(
        (
          await exec(
            'npm',
            ['pack', '--ignore-scripts', '--json', '--pack-destination', temp],
            {cwd, maxBuffer: 4 * 1024 * 1024},
          )
        ).stdout,
      )[0];
      if (cwd === root)
        assert.ok(
          packed.files.every(
            file =>
              !/^(test|tools|generated|assets\/(contract|haskell-contract))\//.test(
                file.path,
              ),
          ),
        );
      tarballs.push(path.join(temp, packed.filename));
    }
    await writeFile(
      path.join(temp, 'package.json'),
      '{"type":"module","private":true}',
    );
    await exec(
      'npm',
      [
        'install',
        '--offline',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        ...tarballs,
      ],
      {cwd: temp, maxBuffer: 4 * 1024 * 1024},
    );
    await mkdir(path.join(temp, 'wit'));
    await writeFile(
      path.join(temp, 'wit/app.wit'),
      'package example:standalone@0.1.0;\ninterface application { echo: func(value: string) -> result<string, string>; }\nworld standalone { export application; }\n',
    );
    await writeFile(
      path.join(temp, 'Application.hs'),
      'module Application (echo) where\nimport Data.Text (Text)\necho :: Text -> IO (Either Text Text)\necho = pure . Right\n',
    );
    await writeFile(
      path.join(temp, 'build.mjs'),
      `import {generateBindings,packageComponent,supportDirectory,runHaskell} from 'wasm-platform-kit-build';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
await generateBindings({wit:'wit',world:'standalone',out:'generated'});
const exports=JSON.parse(await readFile('generated/linker.json','utf8'));
runHaskell('wasm32-wasi-ghc',['-i.','-igenerated','-i'+supportDirectory(),'generated/Main.hs','-outputdir','objects','-o','app.wasm','-no-hs-main','-optl-mexec-model=reactor','-optl-Wl,'+exports.map(x=>'--export='+x).join(',')+',--allow-undefined'],{stdio:'inherit'});
await packageComponent({core:path.resolve('app.wasm'),wit:path.resolve('wit'),world:'standalone',generated:path.resolve('generated'),directory:path.resolve('bundle'),interfaceName:'example:standalone/application@0.1.0'});
const {createApplication}=await import('./bundle/node.mjs');
const host=await createApplication();
try {if(await host.invoke('echo',['日本語 😀'])!=='日本語 😀')throw Error('round trip');}finally{host.close();}
console.log('independent authoring passed');
`,
    );
    const result = await exec(process.execPath, ['build.mjs'], {
      cwd: temp,
      maxBuffer: 8 * 1024 * 1024,
    });
    assert.match(result.stdout, /independent authoring passed/);
    const browser = await readFile(
      path.join(temp, 'bundle/browser.mjs'),
      'utf8',
    );
    assert.match(browser, /manifest/);
    assert.ok(!browser.includes(root));
  },
);
