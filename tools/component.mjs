// Host-owned build pipeline: accepts Wasm and WIT, never plugin JavaScript.
// ref:DEC-host-sdk-direct-haskell
import {execFileSync} from 'node:child_process';
import {format} from 'prettier';
import {declarations} from './facade.mjs';
import {registerLocalNative} from './native.mjs';
import braceStyle from 'prettier-plugin-brace-style';
import {
  readFile,
  writeFile,
  mkdir,
  readdir,
  copyFile,
  rm,
  cp,
} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {generatorPath, runtimeRoot, jcoRoot, toolchainRoot} from './paths.mjs';
/** Identifies exact artifact bytes so the runtime can reject changed components. */
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const run = (tool, args) =>
  execFileSync(tool, args, {stdio: 'pipe', maxBuffer: 32 * 1024 * 1024});
const toolroot = toolchainRoot;
const wasmTools = path.join(toolroot, 'wasmtime/bin/wasm-tools');

/** Builds and registers executable glue from Wasm; callers never provide JavaScript. */
export async function packageComponent({
  core,
  wit,
  world,
  directory,
  generated,
  interfaceName,
  component,
  requirements = [],
})
{
  if (
    !Array.isArray(requirements) ||
    requirements.some(
      requirement =>
        !requirement ||
        typeof requirement.provider !== 'string' ||
        !requirement.provider ||
        ![
          'files',
          'network',
          'storage',
          'environment',
          'ui',
          'native',
        ].includes(requirement.kind),
    )
  )
    throw new Error('invalid informational capability requirements');
  await rm(directory, {recursive: true, force: true});
  await mkdir(directory, {recursive: true});
  const target = path.join(directory, 'component.wasm');
  if (component) await copyFile(component, target);
  else
  {
    run(generatorPath(), [
      'remap',
      core,
      path.join(directory, 'remapped.wasm'),
      path.join(generated, 'symbols.json'),
    ]);
    run(path.join(toolroot, 'binaryen/bin/wasm-merge'), [
      path.join(directory, 'remapped.wasm'),
      'guest',
      path.join(generated, 'initialize.wat'),
      'init',
      '--all-features',
      '--disable-compact-imports',
      '-o',
      path.join(directory, 'initialized.wasm'),
    ]);
    run(wasmTools, [
      'component',
      'embed',
      wit,
      path.join(directory, 'initialized.wasm'),
      '-w',
      world,
      '-o',
      path.join(directory, 'embedded.wasm'),
    ]);
    run(wasmTools, [
      'component',
      'new',
      path.join(directory, 'embedded.wasm'),
      '--adapt',
      `wasi_snapshot_preview1=${path.join(jcoRoot(), 'lib/wasi_snapshot_preview1.reactor.wasm')}`,
      '-o',
      target,
    ]);
    for (const name of ['remapped.wasm', 'initialized.wasm', 'embedded.wasm'])
      await rm(path.join(directory, name));
  }
  run(wasmTools, ['validate', target]);
  const actualWit = run(wasmTools, ['component', 'wit', target]).toString();
  const schemaPath = path.join(directory, 'interface.wit');
  await writeFile(schemaPath, actualWit);
  const contract = JSON.parse(
    run(generatorPath(), ['schema', schemaPath, 'root']),
  );
  await rm(schemaPath);
  if (!contract.interfaces[interfaceName])
    throw new Error('unknown application interface');
  const asyncExports = Object.keys(contract.interfaces[interfaceName]).map(
    name => `${interfaceName}#${name}`,
  );
  run(process.execPath, [
    path.join(jcoRoot(), 'dist/jco.js'),
    'transpile',
    target,
    '-o',
    directory,
    '--name',
    'guest',
    '--instantiation',
    'async',
    '--no-wasi-shim',
    '--base64-cutoff',
    '0',
    '--strict',
    '--async-mode',
    'jspi',
    '--async-imports',
    'host:sdk/host@0.2.0#perform',
    '--async-exports',
    ...asyncExports,
  ]);
  const mapping = path.join(directory, 'bounds.json');
  await writeFile(
    mapping,
    JSON.stringify({memoryBytes: 256 * 1024 * 1024, imports: {}, exports: {}}),
  );
  const assets = {};
  let memoryBudget = 0;
  for (const name of await readdir(directory))
  {
    if (name.endsWith('.wasm') && name !== 'component.wasm')
    {
      const budget = JSON.parse(
        run(generatorPath(), [
          'remap',
          path.join(directory, name),
          path.join(directory, name + '.bounded'),
          mapping,
        ]),
      );
      memoryBudget += budget.memory;
      await copyFile(
        path.join(directory, name + '.bounded'),
        path.join(directory, name),
      );
      await rm(path.join(directory, name + '.bounded'));
    }
    if (name.endsWith('.js') || name.endsWith('.wasm'))
      assets[name] = digest(await readFile(path.join(directory, name)));
  }
  await rm(mapping);
  const manifest = {
    version: 1,
    sdk: '0.2.0',
    component: 'component.wasm',
    sha256: assets['component.wasm'],
    interface: interfaceName,
    contract,
    assets,
    browser: {jspi: true, memory: memoryBudget},
    generators: {
      witParser: '0.263.0',
      jco: '1.41.0',
      bindings: 'wit-haskell-0.2.0',
    },
    requirements: structuredClone(requirements),
    providers: digest(
      Buffer.concat(
        await Promise.all(
          [
            'policy.mjs',
            'node.mjs',
            'browser.mjs',
            'worker.mjs',
            'client.mjs',
          ].map(name => readFile(path.join(runtimeRoot(), name))),
        ),
      ),
    ),
  };
  await writeFile(
    path.join(directory, 'manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n',
  );
  await registerLocalNative({directory, component: target});
  const registration = digest(JSON.stringify(manifest));
  const runtime = path.join(directory, 'runtime');
  await mkdir(runtime, {recursive: true});
  for (const name of ['browser.mjs', 'worker.mjs', 'policy.mjs', 'client.mjs'])
    await copyFile(path.join(runtimeRoot(), name), path.join(runtime, name));
  await cp(
    path.join(runtimeRoot(), 'assets/wasi'),
    path.join(runtime, 'assets/wasi'),
    {recursive: true},
  );
  await writeFile(
    path.join(directory, 'worker.mjs'),
    `// Host-generated allowlist. Plugin manifests cannot modify it.\nimport {startWorker} from './runtime/worker.mjs';\nstartWorker(${JSON.stringify([registration])});\n`,
  );
  await writeFile(
    path.join(directory, 'browser.mjs'),
    `// Generated embedding entrypoint.\nimport {createHost} from './runtime/browser.mjs';\nimport {createClient} from './runtime/client.mjs';\nconst contract = ${JSON.stringify(contract)};\nexport const createApplication = async (options = {}) => createClient(await createHost({...options, manifest: new URL('./manifest.json', import.meta.url), registration: {manifests: ${JSON.stringify([registration])}, workerURL: new URL('./worker.mjs', import.meta.url)}}), contract, ${JSON.stringify(interfaceName)});\n`,
  );
  await writeFile(
    path.join(directory, 'node.mjs'),
    `// Generated Node entrypoint.\nimport {createHost} from 'wasm-platform-kit';\nimport {nativeArtifacts} from './node-registration.mjs';\nimport {createClient} from './runtime/client.mjs';\nconst contract = ${JSON.stringify(contract)};\nexport const createApplication = async (options = {}) => createClient(await createHost({...options, nativeArtifacts, manifest: new URL('./manifest.json', import.meta.url)}), contract, ${JSON.stringify(interfaceName)});\n`,
  );
  const types = declarations(contract, interfaceName);
  for (const file of ['node.d.mts', 'browser.d.mts'])
    await writeFile(path.join(directory, file), types);
  for (const file of [
    'worker.mjs',
    'browser.mjs',
    'node.mjs',
    'node-registration.mjs',
    'install.mjs',
    'node.d.mts',
    'browser.d.mts',
  ])
  {
    const target = path.join(directory, file);
    await writeFile(
      target,
      await format(await readFile(target, 'utf8'), {
        filepath: target,
        printWidth: 80,
        tabWidth: 2,
        singleQuote: true,
        bracketSpacing: false,
        trailingComma: 'all',
        arrowParens: 'avoid',
        plugins: [braceStyle],
        braceStyle: 'allman',
      }),
    );
  }
  await writeFile(
    path.join(directory, 'deployment.json'),
    JSON.stringify(
      {
        standard: {
          'Content-Security-Policy':
            "default-src 'self'; script-src 'self' blob: 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'",
        },
        isolated: {
          'Cross-Origin-Opener-Policy': 'same-origin',
          'Cross-Origin-Embedder-Policy': 'require-corp',
        },
      },
      null,
      2,
    ),
  );
  return manifest;
}
