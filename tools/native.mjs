// Native build products are registered by trusted packaging code, never a guest.
// ref:DEC-host-sdk-precompiled-node
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createReadStream, constants} from 'node:fs';
import {mkdir, readFile, writeFile, copyFile} from 'node:fs/promises';
import path from 'node:path';
import {format} from 'prettier';
import braceStyle from 'prettier-plugin-brace-style';
import {compilerPath} from './paths.mjs';

export const nativeTargets = Object.freeze({
  'darwin-arm64': 'aarch64-apple-darwin',
  'darwin-x64': 'x86_64-apple-darwin',
  'linux-arm64': 'aarch64-unknown-linux-gnu',
  'linux-x64': 'x86_64-unknown-linux-gnu',
});
const configuration = 'host-sdk-0.2.0/wasmtime-50.0.1/fuel-v1';

/** Hashes bounded native files without allocating their full contents. ref:DEC-host-sdk-precompiled-node */
async function nativeDigest(file)
{
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of createReadStream(file))
  {
    size += chunk.length;
    if (size > 512 * 1024 * 1024)
      throw new Error('native artifact size exhausted');
    hash.update(chunk);
  }
  return hash.digest('hex');
}

/** Compiles portable Wasm on the selected build host. ref:DEC-host-sdk-precompiled-node */
export function precompileNative({component, output, target})
{
  return JSON.parse(
    execFileSync(
      compilerPath(),
      ['--precompile', component, output, ...(target ? [target] : [])],
      {
        encoding: 'utf8',
        maxBuffer: 1024 * 1024,
      },
    ),
  );
}

/** Emits executable authority from trusted, verified build receipts. ref:DEC-host-sdk-precompiled-node */
async function writeRegistration(directory, entries)
{
  const manifest = JSON.parse(
    await readFile(path.join(directory, 'manifest.json'), 'utf8'),
  );
  const items = Object.entries(entries).map(([platform, entry]) =>
  {
    const {file, package: packageName, ...registration} = entry;
    const location = packageName
      ? `get artifact() { try { return pathToFileURL(require.resolve(${JSON.stringify(packageName + '/component.cwasm')})); } catch (cause) { const error = new Error(${JSON.stringify('Native package ' + packageName + ' is unavailable; reinstall with scripts enabled or run npm rebuild.')}, {cause}); error.code = 'unsupported'; throw error; } }`
      : `artifact: new URL(${JSON.stringify('./' + file)}, import.meta.url)`;
    return `${JSON.stringify(platform)}: Object.freeze({...${JSON.stringify(registration)}, ${location}})`;
  });
  await writeFile(
    path.join(directory, 'native-artifacts.json'),
    JSON.stringify(entries, null, 2) + '\n',
  );
  await writeFile(path.join(directory, '.npmignore'), '.native/\n');
  await writeFile(
    path.join(directory, 'install.mjs'),
    `// Generated installation bootstrap. ref:DEC-wpk-installation-preparation\nimport {prepareNative} from 'wasm-platform-kit/install';\nimport {prebuiltArtifacts} from './node-registration.mjs';\nawait prepareNative({directory: new URL('./', import.meta.url), component: new URL(${JSON.stringify(manifest.component)}, import.meta.url), componentSha256: ${JSON.stringify(manifest.sha256)}, prebuiltArtifacts});\n`,
  );
  await writeFile(
    path.join(directory, 'node-registration.mjs'),
    await format(
      `// Trusted build output. Guest manifests cannot replace this authority.\nimport {installedNativeArtifacts} from 'wasm-platform-kit/native-registration';\nimport {createRequire} from 'node:module';\nimport {pathToFileURL} from 'node:url';\nconst require = createRequire(import.meta.url);\nexport const prebuiltArtifacts = Object.freeze({${items.join(',')}});\nexport const nativeArtifacts = installedNativeArtifacts({directory: new URL('./', import.meta.url), componentSha256: ${JSON.stringify(manifest.sha256)}, prebuiltArtifacts});\n`,
      {
        parser: 'babel',
        printWidth: 80,
        tabWidth: 2,
        singleQuote: true,
        bracketSpacing: false,
        trailingComma: 'all',
        arrowParens: 'avoid',
        plugins: [braceStyle],
        braceStyle: 'allman',
      },
    ),
  );
}

/** Registers one local inline artifact during component construction. ref:DEC-host-sdk-precompiled-node */
export async function registerLocalNative({directory, component})
{
  const platform = `${process.platform}-${process.arch}`;
  if (!nativeTargets[platform])
    throw new Error(`unsupported native target ${platform}`);
  const file = `component.${platform}.cwasm`;
  const registration = precompileNative({
    component,
    output: path.join(directory, file),
  });
  await writeRegistration(directory, {[platform]: {...registration, file}});
}

/** Combines trusted native builds into optional per-platform npm packages. ref:DEC-host-sdk-precompiled-node */
export async function packageNativeArtifacts({
  directory,
  artifacts,
  packageDirectory,
  packagePrefix,
  version,
  licenseFile,
  license = 'UNLICENSED',
})
{
  if (
    packagePrefix !== undefined &&
    (!/^(?:@[a-z0-9-]+\/)?[a-z0-9-]+$/.test(packagePrefix) ||
      !/^\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?$/.test(version))
  )
    throw new Error('invalid native package name or version');
  const manifest = JSON.parse(
    await readFile(path.join(directory, 'manifest.json'), 'utf8'),
  );
  const entries = {};
  const dependencies = {};
  // Validate every input before emitting registration or modifying package outputs.
  for (const {platform, file, registration} of artifacts)
  {
    if (
      !nativeTargets[platform] ||
      entries[platform] ||
      registration.target !== nativeTargets[platform] ||
      registration.configuration !== configuration ||
      registration.componentSha256 !== manifest.sha256 ||
      registration.nativeSha256 !== (await nativeDigest(file))
    )
      throw new Error(`native build registration mismatch: ${platform}`);
    entries[platform] = {
      componentSha256: registration.componentSha256,
      nativeSha256: registration.nativeSha256,
      configuration: registration.configuration,
      target: registration.target,
      ...(packagePrefix
        ? {package: `${packagePrefix}-${platform}`}
        : {file: `component.${platform}.cwasm`}),
    };
  }
  if (artifacts.length === 0) throw new Error('native artifacts required');
  for (const {platform, file} of artifacts)
  {
    if (!packagePrefix)
    {
      const destination = path.join(directory, entries[platform].file);
      if (path.resolve(file) !== path.resolve(destination))
        await copyFile(file, destination);
      continue;
    }
    const output = path.join(packageDirectory, platform);
    await mkdir(output, {recursive: true});
    await copyFile(
      file,
      path.join(output, 'component.cwasm'),
      constants.COPYFILE_FICLONE,
    );
    if (licenseFile) await copyFile(licenseFile, path.join(output, 'LICENSE'));
    const [os, cpu] = platform.split('-');
    await writeFile(
      path.join(output, 'package.json'),
      JSON.stringify(
        {
          name: entries[platform].package,
          version,
          license,
          os: [os],
          cpu: [cpu],
          ...(os === 'linux' ? {libc: ['glibc']} : {}),
          files: ['component.cwasm', 'LICENSE'],
          exports: {'./component.cwasm': './component.cwasm'},
        },
        null,
        2,
      ) + '\n',
    );
    dependencies[entries[platform].package] = version;
  }
  await writeRegistration(directory, entries);
  return dependencies;
}
