// Native helpers can be built from Rust without the Haskell application toolchain.
// ref:DEC-host-sdk-precompiled-node
import {execFileSync} from 'node:child_process';
import {
  readFile,
  writeFile,
  mkdir,
  copyFile,
  symlink,
  rm,
} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
import path from 'node:path';
import {inspectLinuxAbi} from './abi.mjs';
import {nativeTargets} from './native.mjs';

/** Supported executable formats and machine identifiers. ref:DEC-host-sdk-precompiled-node */
const targets = {
  'darwin-arm64': {
    os: 'darwin',
    cpu: 'arm64',
    magic: 0xfeedfacf,
    machine: 0x100000c,
  },
  'darwin-x64': {
    os: 'darwin',
    cpu: 'x64',
    magic: 0xfeedfacf,
    machine: 0x1000007,
  },
  'linux-arm64': {os: 'linux', cpu: 'arm64', magic: 0x464c457f, machine: 183},
  'linux-x64': {os: 'linux', cpu: 'x64', magic: 0x464c457f, machine: 62},
};
/** Anchors build inputs and staging paths in the SDK checkout. ref:DEC-host-sdk-precompiled-node */
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Stages native builds with verified executable architecture and exact digests. ref:DEC-host-sdk-precompiled-node */
export async function buildPlatform({
  platform = `${process.platform}-${process.arch}`,
  build = true,
} = {})
{
  /** Rejects platforms without an explicit executable contract. ref:DEC-host-sdk-precompiled-node */
  const target = targets[platform];
  if (!target) throw new Error(`unsupported native platform ${platform}`);
  if (build && target.os === 'darwin' && process.platform !== 'darwin')
    throw new Error('macOS native builds require a macOS build host');
  /** Stages only the selected target's distribution. ref:DEC-host-sdk-precompiled-node */
  const directory = path.join(root, 'platforms', platform);
  await mkdir(path.join(directory, 'bin'), {recursive: true});
  if (build)
  {
    /** Resolves relative Cargo output paths against its working directory. ref:DEC-host-sdk-linux-abi-baseline */
    const output = path.resolve(root, process.env.CARGO_TARGET_DIR ?? 'target');
    if (process.env.CARGO_BUILD_TARGET)
      throw new Error('native builder does not accept implicit cross targets');
    /** Distinguishes host and target architecture. ref:DEC-host-sdk-precompiled-node */
    const cross = platform !== `${process.platform}-${process.arch}`;
    /** Uses the same target triple as native component generation. ref:DEC-host-sdk-precompiled-node */
    const rustTarget = nativeTargets[platform];
    /** Linux always selects an explicit glibc baseline target. ref:DEC-host-sdk-linux-abi-baseline */
    const targeted = cross || target.os === 'linux';
    /** Reads the selected Cargo target's release outputs. ref:DEC-host-sdk-linux-abi-baseline */
    const release = path.join(
      output,
      ...(targeted ? [rustTarget] : []),
      'release',
    );
    /** Uses upstream Cargo Zigbuild for the Linux ABI baseline. ref:DEC-host-sdk-linux-abi-baseline */
    const cargo = args =>
      execFileSync(
        'cargo',
        [
          target.os === 'linux' ? 'zigbuild' : 'build',
          '--locked',
          '--release',
          ...(targeted
            ? ['--target', rustTarget + (target.os === 'linux' ? '.2.28' : '')]
            : []),
          ...args,
        ],
        {
          cwd: root,
          stdio: 'inherit',
        },
      );
    cargo(['-p', 'host-sdk-runtime']);
    await copyFile(
      path.join(release, 'host-sdk-runtime'),
      path.join(directory, 'bin/host-sdk-runtime'),
    );
    cargo(['-p', 'host-sdk-runtime', '--features', 'compiler']);
    await copyFile(
      path.join(release, 'host-sdk-runtime'),
      path.join(directory, 'bin/host-sdk-source-runtime'),
    );
    cargo(['-p', 'wit-haskell']);
    await copyFile(
      path.join(release, 'wit-haskell'),
      path.join(directory, 'bin/wit-haskell'),
    );
  }
  /** Binds staged executables to their engine and platform. ref:DEC-host-sdk-precompiled-node */
  const integrity = {runtime: 'wasmtime-50.0.1', platform};
  /** Checks every executable exposed by the platform package. ref:DEC-host-sdk-precompiled-node */
  for (const [file, key] of [
    ['host-sdk-runtime', 'sha256'],
    ['host-sdk-source-runtime', 'sourceRuntime'],
    ['wit-haskell', 'generator'],
  ])
  {
    /** Hashes the same bytes whose architecture is checked. ref:DEC-host-sdk-precompiled-node */
    const bytes = await readFile(path.join(directory, 'bin', file));
    /** Extracts the native format's machine identifier. ref:DEC-host-sdk-precompiled-node */
    const machine =
      target.os === 'darwin' ? bytes.readUInt32LE(4) : bytes.readUInt16LE(18);
    if (bytes.readUInt32LE(0) !== target.magic || machine !== target.machine)
      throw new Error(`executable architecture mismatch: ${platform}/${file}`);
    if (target.os === 'linux')
    {
      /** Records the inspected requirement after rejecting newer symbols. ref:DEC-host-sdk-linux-abi-baseline */
      const minimum = inspectLinuxAbi(path.join(directory, 'bin', file));
      (integrity.minimumGlibc ??= {})[file] = minimum;
    }
    integrity[key] = createHash('sha256').update(bytes).digest('hex');
  }
  /** Keeps helper package versions aligned with the reusable SDK. ref:DEC-host-sdk-precompiled-node */
  const version = JSON.parse(
    await readFile(path.join(root, 'package.json'), 'utf8'),
  ).version;
  await copyFile(path.join(root, 'LICENSE'), path.join(directory, 'LICENSE'));
  await writeFile(
    path.join(directory, 'integrity.json'),
    JSON.stringify(integrity, null, 2) + '\n',
  );
  await writeFile(
    path.join(directory, 'package.json'),
    JSON.stringify(
      {
        name: `wasm-platform-kit-${platform}`,
        version,
        license: 'MIT',
        os: [target.os],
        cpu: [target.cpu],
        ...(target.os === 'linux' ? {libc: ['glibc']} : {}),
        files: ['bin', 'integrity.json', 'LICENSE'],
        exports: Object.fromEntries(
          ['host-sdk-runtime', 'host-sdk-source-runtime', 'wit-haskell'].map(
            name => [`./bin/${name}`, `./bin/${name}`],
          ),
        ),
      },
      null,
      2,
    ) + '\n',
  );
  {
    /** Provides package resolution for local SDK conformance tests. ref:DEC-host-sdk-precompiled-node */
    const parent = path.join(root, 'node_modules');
    await mkdir(parent, {recursive: true});
    /** Replaces only this SDK-owned platform package link. ref:DEC-host-sdk-precompiled-node */
    const link = path.join(parent, `wasm-platform-kit-${platform}`);
    await rm(link, {recursive: true, force: true});
    await symlink(directory, link);
  }
  return directory;
}

if (
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
)
{
  /** Accepts explicit staging or building for one supported platform. ref:DEC-host-sdk-precompiled-node */
  const args = process.argv.slice(2);
  if (
    args.length &&
    (args.length !== 2 || !['--stage', '--build'].includes(args[0]))
  )
    throw new Error(
      'usage: platform.mjs [--stage|--build darwin-arm64|darwin-x64|linux-arm64|linux-x64]',
    );
  await buildPlatform(
    args.length ? {platform: args[1], build: args[0] === '--build'} : {},
  );
}
