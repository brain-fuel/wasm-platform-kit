import {stageBuildPackage} from './stage-build.mjs';
// Builds SDK distributions and generic conformance fixtures without an application checkout.
import {execFileSync} from 'node:child_process';
import {mkdir, copyFile, cp, readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {generateBindings} from './generate.mjs';
import {packageComponent} from './component.mjs';
import {runHaskell} from './paths.mjs';
import {buildPlatform} from './platform.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const run = (cmd, args) =>
  execFileSync(cmd, args, {cwd: root, stdio: 'inherit'});
const platform = `${process.platform}-${process.arch}`;
await buildPlatform();
// Reuse upstream WASI implementation unchanged.
const wasi = path.resolve(
  path.dirname(require.resolve('@bytecodealliance/preview2-shim')),
  '..',
);
await cp(path.join(wasi, 'browser'), path.join(root, 'assets/wasi'), {
  recursive: true,
});
await copyFile(
  path.resolve(wasi, '../LICENSE'),
  path.join(root, 'assets/wasi/LICENSE'),
);
await stageBuildPackage();
// Test artifacts are deliberately excluded from both npm packages.
await generateBindings({
  wit: path.join(root, 'test/wit'),
  world: 'contract',
  out: path.join(root, 'generated'),
});
const exported = JSON.parse(
  await readFile(path.join(root, 'generated/linker.json'), 'utf8'),
);
runHaskell(
  'wasm32-wasi-ghc',
  [
    '-itest/fixtures',
    '-igenerated',
    '-ihaskell',
    'generated/Main.hs',
    '-outputdir',
    'generated/fixture-objects',
    '-o',
    'generated/fixture.wasm',
    '-no-hs-main',
    '-optl-mexec-model=reactor',
    `-optl-Wl,${exported.map(x => '--export=' + x).join(',')},--allow-undefined`,
  ],
  {cwd: root, stdio: 'inherit'},
);
await packageComponent({
  core: path.join(root, 'generated/fixture.wasm'),
  wit: path.join(root, 'test/wit'),
  world: 'contract',
  generated: path.join(root, 'generated'),
  directory: path.join(root, 'assets/haskell-contract'),
  interfaceName: 'host:contract/application@0.2.0',
});
run('cargo', [
  'build',
  '--locked',
  '--release',
  '-p',
  'host-sdk-contract-guest',
  '--target',
  'wasm32-wasip2',
]);
await packageComponent({
  component: path.join(
    root,
    'target/wasm32-wasip2/release/host_sdk_contract_guest.wasm',
  ),
  directory: path.join(root, 'assets/contract'),
  interfaceName: 'host:contract/application@0.2.0',
  requirements: [{provider: 'files', kind: 'files'}],
});
console.log(
  `Built independent SDK, build tools and ${platform} platform package.`,
);
