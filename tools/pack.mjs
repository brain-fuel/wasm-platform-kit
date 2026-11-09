// Publishes nothing: produces the exact tarballs applications install locally.
import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, writeFile, readdir, readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {inspectLinuxAbi} from './abi.mjs';
/** Resolves distributions against the SDK checkout. ref:DEC-host-sdk-precompiled-node */
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
/** Holds local archives without publishing them. ref:DEC-host-sdk-precompiled-node */
const destination = path.join(root, 'dist');
await mkdir(destination, {recursive: true});
/** Records exact npm archive identities for consumers. ref:DEC-host-sdk-precompiled-node */
const packages = {};
/** Includes only explicitly supported staged platforms. ref:DEC-host-sdk-precompiled-node */
const platforms = (await readdir(path.join(root, 'platforms'))).filter(
  platform =>
    ['darwin-arm64', 'darwin-x64', 'linux-arm64', 'linux-x64'].includes(
      platform,
    ) && existsSync(path.join(root, 'platforms', platform, 'package.json')),
);
/** Keeps each native helper archive separately selectable. ref:DEC-host-sdk-precompiled-node */
const platformPackages = {};
// A failed or concurrent rebuild must not pack binaries against stale receipts.
// ref:DEC-host-sdk-linux-abi-baseline
for (const platform of platforms)
{
  /** Locates this platform's staged executables. ref:DEC-host-sdk-linux-abi-baseline */
  const directory = path.join(root, 'platforms', platform);
  /** Requires the receipt emitted by successful platform staging. ref:DEC-host-sdk-linux-abi-baseline */
  const integrity = JSON.parse(
    await readFile(path.join(directory, 'integrity.json'), 'utf8'),
  );
  /** Verifies execution, compilation and binding-generation binaries. ref:DEC-host-sdk-linux-abi-baseline */
  for (const [file, key] of [
    ['host-sdk-runtime', 'sha256'],
    ['host-sdk-source-runtime', 'sourceRuntime'],
    ['wit-haskell', 'generator'],
  ])
  {
    /** Selects the exact executable that npm will package. ref:DEC-host-sdk-linux-abi-baseline */
    const binary = path.join(directory, 'bin', file);
    /** Rejects a changed executable before archive creation. ref:DEC-host-sdk-linux-abi-baseline */
    const actual = createHash('sha256')
      .update(await readFile(binary))
      .digest('hex');
    if (actual !== integrity[key])
      throw new Error(`staged native helper changed: ${platform}/${file}`);
    if (
      platform.startsWith('linux-') &&
      inspectLinuxAbi(binary) !== integrity.minimumGlibc?.[file]
    )
      throw new Error(`missing or stale ABI receipt: ${platform}/${file}`);
  }
}
/** Packs the validated platform artifacts and reusable SDK packages. ref:DEC-host-sdk-precompiled-node */
for (const [name, dir] of [
  ...platforms.map(platform => [
    `platform:${platform}`,
    `platforms/${platform}`,
  ]),
  ['runtime', '.'],
  ['build', 'packages/build'],
])
{
  /** npm supplies the final archive's identity. ref:DEC-host-sdk-precompiled-node */
  const result = JSON.parse(
    execFileSync(
      'npm',
      ['pack', '--ignore-scripts', '--json', '--pack-destination', destination],
      {cwd: path.join(root, dir), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024},
    ),
  )[0];
  /** Consumers pin the archive rather than importing checkout sources. ref:DEC-host-sdk-precompiled-node */
  const record = {
    file: result.filename,
    integrity: result.integrity,
    shasum: result.shasum,
  };
  if (name.startsWith('platform:')) platformPackages[name.slice(9)] = record;
  else packages[name] = record;
}
packages.platforms = platformPackages;
packages.platform = platformPackages[`${process.platform}-${process.arch}`];
await writeFile(
  path.join(destination, 'packages.json'),
  JSON.stringify(packages, null, 2) + '\n',
);
console.log(JSON.stringify(packages, null, 2));
